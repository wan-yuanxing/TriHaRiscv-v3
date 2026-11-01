"""Admission tests use real immutable Git objects, never the source checkout."""
import importlib.util
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('import_b03', HERE / 'import_b03.py')
IMPL = None
if Path(SPEC.origin).is_file():
    IMPL = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(IMPL)


class AdmissionExists(unittest.TestCase):
    def test_importer_exists(self):
        self.assertIsNotNone(IMPL, 'immutable B03 source importer has not been implemented')


@unittest.skipIf(IMPL is None, 'importer absent')
class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / 'upstream'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'core.autocrlf', 'false')
        self.put('rtl/top.v', b'`include "width.vh"\r\nmodule top; child #(.N(2)) u_child(); GTP_LUT1 #(.INIT(2)) u_lut(); endmodule\r\n')
        self.put('rtl/width.vh', b'`define WIDTH 4\n')
        self.put('rtl/child.v', b'module child #(parameter N=1)(); endmodule\n')
        self.put('rtl/not_selected.v', b'module other(); child unused(); endmodule\n')
        self.git('add', 'rtl')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
        self.ref = self.git('rev-parse', 'HEAD').decode().strip()
        self.project = Path(self.tmp.name) / 'main'
        self.project.mkdir()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.PIPE)

    def put(self, name, data):
        p = self.repo / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def plan(self):
        return IMPL.plan_import(self.repo, self.ref, ['top'])

    def test_exact_reachable_closure_ignores_dirty_worktree(self):
        self.put('rtl/child.v', b'BROKEN LOCAL EDIT\n')
        manifest, blobs = self.plan()
        self.assertEqual(set(blobs), {'rtl/top.v', 'rtl/width.vh', 'rtl/child.v'})
        self.assertEqual(blobs['rtl/child.v'], b'module child #(parameter N=1)(); endmodule\n')
        self.assertEqual(manifest['external_modules'], ['GTP_LUT1'])
        self.assertEqual(manifest['source_commit'], self.ref)

    def test_import_is_byte_exact_and_checkable_without_git(self):
        manifest, blobs = self.plan()
        IMPL.materialize(self.project, manifest, blobs)
        result = IMPL.verify_import(self.project, trusted_manifest=manifest)
        self.assertEqual(result['files'], 3)
        dest = self.project / IMPL.DESTINATION / 'rtl/top.v'
        self.assertEqual(dest.read_bytes(), blobs['rtl/top.v'])
        self.assertIn(b'\r\n', dest.read_bytes())
        lines = (self.project / IMPL.FILELIST).read_text().splitlines()
        self.assertEqual(lines, [IMPL.DESTINATION + '/' + n for n in sorted(blobs) if n.endswith('.v')])

    def test_tampered_source_is_rejected(self):
        manifest, blobs = self.plan()
        IMPL.materialize(self.project, manifest, blobs)
        (self.project / IMPL.DESTINATION / 'rtl/child.v').write_text('bad')
        with self.assertRaisesRegex(ValueError, 'SHA256'):
            IMPL.verify_import(self.project, trusted_manifest=manifest)

    def test_filelist_injection_is_rejected(self):
        manifest, blobs = self.plan()
        IMPL.materialize(self.project, manifest, blobs)
        with (self.project / IMPL.FILELIST).open('a') as stream:
            stream.write('rtl/not_selected.v\n')
        with self.assertRaisesRegex(ValueError, 'filelist'):
            IMPL.verify_import(self.project, trusted_manifest=manifest)

    def test_conflict_is_detected_before_any_write(self):
        manifest, blobs = self.plan()
        p = self.project / IMPL.DESTINATION / 'rtl/top.v'
        p.parent.mkdir(parents=True)
        p.write_text('user file')
        with self.assertRaisesRegex(ValueError, 'existing'):
            IMPL.materialize(self.project, manifest, blobs)
        self.assertEqual(p.read_text(), 'user file')
        self.assertFalse((p.parent / 'child.v').exists())

    def test_nonimmutable_ref_and_missing_root_rejected(self):
        with self.assertRaisesRegex(ValueError, '40'):
            IMPL.plan_import(self.repo, 'HEAD', ['top'])
        with self.assertRaisesRegex(ValueError, 'missing root'):
            IMPL.plan_import(self.repo, self.ref, ['no_such_module'])

    def test_reachable_duplicate_module_is_rejected(self):
        self.put('rtl/duplicate.v', b'module child(); endmodule\n')
        self.git('add', 'rtl/duplicate.v')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'duplicate')
        ref = self.git('rev-parse', 'HEAD').decode().strip()
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            IMPL.plan_import(self.repo, ref, ['top'])

    def test_unknown_module_and_missing_include_rejected(self):
        self.put('rtl/top.v', b'module top; unknown_leaf u_leaf(); endmodule\n')
        self.git('add', 'rtl/top.v')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'unknown')
        ref = self.git('rev-parse', 'HEAD').decode().strip()
        with self.assertRaisesRegex(ValueError, 'unknown module'):
            IMPL.plan_import(self.repo, ref, ['top'])
        self.put('rtl/top.v', b'`include "absent.vh"\nmodule top; endmodule\n')
        self.git('add', 'rtl/top.v')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'include')
        ref = self.git('rev-parse', 'HEAD').decode().strip()
        with self.assertRaisesRegex(ValueError, 'include'):
            IMPL.plan_import(self.repo, ref, ['top'])

    def test_manifest_path_escape_and_blob_tamper_rejected(self):
        manifest, blobs = self.plan()
        blobs['rtl/child.v'] += b'changed'
        with self.assertRaisesRegex(ValueError, 'SHA256'):
            IMPL.materialize(self.project, manifest, blobs)
        manifest, blobs = self.plan()
        manifest['files'][0]['path'] = '../escape.v'
        with self.assertRaises(ValueError):
            IMPL.materialize(self.project, manifest, blobs)

    def test_generate_block_labels_are_not_instances(self):
        source = 'module top; genvar i; generate for(i=0;i<2;i=i+1)begin:identity_key for(j=0;j<2;j=j+1)begin:word_bit child u(); end end endgenerate endmodule'
        self.assertEqual(IMPL.instances(source), {'child'})

    def test_deterministic_plan_across_hash_seeds(self):
        self.put('rtl/child.v', b'module child; alpha a(); beta b(); gamma c(); endmodule\n')
        for name in ('alpha', 'beta', 'gamma'):
            self.put('rtl/' + name + '.v', ('module ' + name + '; endmodule\n').encode())
        self.git('add', 'rtl')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'branches')
        self.ref = self.git('rev-parse', 'HEAD').decode().strip()
        script = 'import import_b03,json,sys; print(json.dumps(import_b03.plan_import(sys.argv[1],sys.argv[2],["top"])[0]))'
        outputs = [subprocess.check_output([sys.executable, '-c', script, str(self.repo), self.ref],
                    cwd=HERE, env={**os.environ, 'PYTHONHASHSEED': str(seed)}) for seed in (1,2,3)]
        self.assertEqual(len(set(outputs)), 1)

    def test_include_body_dependencies_are_resolved(self):
        self.put('rtl/top.v', b'module top; `include "body.vh"\nendmodule\n')
        self.put('rtl/body.vh', b'child u_child();\n')
        self.git('add', 'rtl')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'body')
        self.ref = self.git('rev-parse', 'HEAD').decode().strip()
        _, blobs = self.plan()
        self.assertEqual(set(blobs), {'rtl/top.v', 'rtl/body.vh', 'rtl/child.v'})

    def test_windows_unsafe_paths_rejected(self):
        for path in ('rtl/bad\nname.v', 'rtl/CON.v', 'rtl/trailing./a.v', 'rtl/a"b.v', 'rtl/NUL.txt'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                IMPL.safe_path(path)

    def test_extra_destination_hdl_rejected_before_writing(self):
        p = self.project / IMPL.DESTINATION / 'rtl/old.v'
        p.parent.mkdir(parents=True)
        p.write_bytes(b'old')
        manifest, blobs = self.plan()
        with self.assertRaises(ValueError):
            IMPL.materialize(self.project, manifest, blobs)
        self.assertFalse((p.parent / 'top.v').exists())

    def test_macro_include_rejected(self):
        self.put('rtl/top.v', b'`define INC "body.vh"\n`include `INC\nmodule top; endmodule\n')
        self.git('add', 'rtl')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'macro')
        self.ref = self.git('rev-parse', 'HEAD').decode().strip()
        with self.assertRaisesRegex(ValueError, 'include'):
            self.plan()

    def test_metadata_mutations_are_rejected_against_trusted_manifest(self):
        manifest, blobs = self.plan()
        IMPL.materialize(self.project, manifest, blobs)
        path = self.project / IMPL.DESTINATION / 'UPSTREAM.json'
        mutations = [('source_commit', '0'*40), ('root_modules', ['board']),
                     ('module_dependencies', {}), ('external_modules', ['hmic_ddr3'])]
        for key, value in mutations:
            altered = copy.deepcopy(manifest)
            altered[key] = value
            path.write_text(json.dumps(altered))
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'trusted'):
                IMPL.verify_import(self.project, trusted_manifest=manifest)
        altered = copy.deepcopy(manifest)
        altered['files'][0]['git_blob'] = '0'*40
        path.write_text(json.dumps(altered))
        with self.assertRaisesRegex(ValueError, 'Git blob'):
            IMPL.verify_import(self.project, trusted_manifest=altered)

    def test_case_collision_rejected(self):
        blobs = {'rtl/top.v': b'module top; endmodule', 'rtl/TOP.v': b'module extra; endmodule'}
        with self.assertRaisesRegex(ValueError, 'collision'):
            IMPL.dependency_closure(blobs, ['top'])

    def test_non_directory_parent_rejected_before_writing(self):
        parent = self.project / IMPL.DESTINATION
        parent.parent.mkdir(parents=True)
        parent.write_bytes(b'not a directory')
        manifest, blobs = self.plan()
        with self.assertRaisesRegex(ValueError, 'ancestor'):
            IMPL.materialize(self.project, manifest, blobs)
        self.assertFalse((self.project / IMPL.FILELIST).exists())


if __name__ == '__main__':
    unittest.main()
