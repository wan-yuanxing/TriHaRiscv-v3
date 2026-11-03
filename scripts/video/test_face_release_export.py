"""Small synthetic transport fixtures; these never certify FPGA timing or hardware."""
import json
from pathlib import Path
import shutil
import unittest
from unittest.mock import patch
from datetime import datetime, timezone

import export_face_release as exporter
from face_profiles import PROFILES
from restore_face_release import digest, install, verify


WORK = exporter.ROOT/'build/video'/('release_export_tests_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.root=WORK/self._testMethodName
        self.root.mkdir(parents=True,exist_ok=False)
        self.output=self.root/'release'
        self.base=self.root/'build/map'
        self.qualified=self.root/'build/qualified/result.json'
        self.source=self.write('rtl/fixture.v',b'// synthetic transport fixture, not an FPGA design\n')
        for name in ('program_board.py','restore_face_release.py','export_face_release.py'):
            self.write('scripts/video/'+name,('// fixture '+name+'\n').encode())
        self.write('scripts/soc/upload_face_model.py',b'# fixture uploader\n')
        for directory in ('build/video/vendor','build/npu/b03_assets_20261030','build/npu/face_fixture_20261103'):
            self.write(directory+'/fixture.bin',directory.encode())
        old_report=self.write('build/old-placement/report.txt',b'original measured placement provenance\n')
        placed=self.write('build/placement/placed.adf',b'fixture placed database\n')
        placement=self.write_json('build/placement/receipt.json',{'inputs':{str(placed):digest(placed),str(old_report):digest(old_report)}})
        mapped=self.write('build/map/map.adf',b'fixture mapped database\n')
        self.write_json('build/map/result.json',{'mapping_inputs':{str(mapped):digest(mapped)}})
        self.routed=self.write('build/route/routed.adf',b'fixture routed database\n')
        route=self.write_json('build/route/receipt.json',{'status':'ROUTE_REVIEW_READY','routed_db':str(self.routed),
            'inputs':{str(placement):digest(placement),str(mapped):digest(mapped)}})
        functional=[]
        for case in ('positive','negative'):
            directory=self.root/'build'/case
            log=self.write('build/'+case+'/simulation.log',b'synthetic transport fixture; not a simulation acceptance\n')
            result=self.write_json('build/'+case+'/result.json',{'status':'PASS',
                'source_sha256':{'rtl/fixture.v':digest(self.source)},'output_sha256':{'simulation.log':digest(log)}})
            functional.append({'directory':str(directory),'result_sha256':digest(result)})
        bit=self.write('build/qualified/generate_bitstream/triha_face_board_top.sbit',b'NOT A PROGRAMMABLE BITSTREAM\n')
        mask=self.write('build/qualified/generate_bitstream/triha_face_board_top.smsk',b'NOT A PROGRAMMABLE MASK\n')
        for name in ('rom.hex','sram.hex','firmware.elf'):
            self.write('build/qualified/'+name,('fixture '+name+'\n').encode())
        self.q={'status':'pass','stage':'bitstream','face_profile':'avatar','top_parameters':PROFILES['avatar'],
            'internal_timing_met':True,'cdc_timing_met':True,'input_snapshot_verified_before_and_after_build':True,
            'source_build_directory':str(self.base),'inputs':{'rtl/fixture.v':digest(self.source)},
            'evidence_inputs':{str(route):digest(route),str(self.routed):digest(self.routed)},'functional':functional,
            'artifact':bit.relative_to(self.root).as_posix(),'artifact_sha256':digest(bit),
            'verify_mask':mask.relative_to(self.root).as_posix(),'verify_mask_sha256':digest(mask),
            'bitstream_generation_inputs':{'fixture/pds_shell.exe':'0'*64}}
        self.save_qualification()
        self.patch=patch.object(exporter,'ROOT',self.root)
        self.patch.start();self.addCleanup(self.patch.stop)

    def write(self,name,data):
        path=self.root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);return path

    def write_json(self,name,data):
        return self.write(name,(json.dumps(data,indent=2)+'\n').encode())

    def save_qualification(self):
        self.write_json('build/qualified/result.json',self.q)
        package='build/video/releases/triha_face_board_'+self.q['artifact_sha256'][:12]
        self.write(package+'/manifest.json',self.qualified.read_bytes())
        for name in ('README.txt','message_review.json','timing.rtr'):
            self.write(package+'/'+name,b'{}\n' if name.endswith('.json') else b'transport fixture only\n')

    def export(self):
        # Git commit lookup records provenance only; no git checkout is changed.
        exporter.export(self.qualified,self.output,[])

    def test_round_trip_and_recursive_placement(self):
        self.export()
        manifest=verify(self.output,self.root)
        for name in ('build/placement/placed.adf','build/old-placement/report.txt','build/route/routed.adf'):
            self.assertIn(name,manifest['archive_members'])
        target=self.root/'restored';target.mkdir()
        for name in manifest['source_sha256']:
            path=target/name;path.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(self.root/name,path)
        verify(self.output,target)
        restored=install(self.output,target,manifest)
        self.assertGreater(restored,len(manifest['archive_members']))
        for name,expected in manifest['archive_members'].items():
            self.assertEqual(digest(target/name),expected['sha256'])
        package=target/manifest['package_directory']
        self.assertEqual(digest(package/'triha_face_board_top.sbit'),self.q['artifact_sha256'])
        self.assertEqual(json.loads((target/'build/video/latest_package_triha_face_board.json').read_text())['physical_board'],False)

    def test_changed_native_evidence_rejected(self):
        self.routed.write_bytes(b'tampered route')
        with self.assertRaisesRegex(ValueError,'Qualified evidence changed'):self.export()
        self.assertFalse(self.output.exists())

    def test_changed_source_rejected(self):
        self.source.write_bytes(b'tampered source')
        with self.assertRaisesRegex(ValueError,'Qualified source changed'):self.export()
        self.assertFalse(self.output.exists())

    def test_changed_nested_placement_rejected(self):
        (self.root/'build/placement/placed.adf').write_bytes(b'tampered placement')
        with self.assertRaisesRegex(ValueError,'Bound build input changed'):self.export()
        self.assertFalse(self.output.exists())

    def test_unqualified_result_rejected(self):
        self.q['internal_timing_met']=False;self.save_qualification()
        with self.assertRaisesRegex(ValueError,'fully qualified bitstream'):self.export()
        self.assertFalse(self.output.exists())

    def test_input_mutated_while_archiving_rejected(self):
        original=exporter.zipfile.ZipFile
        def open_archive(filename,mode='r',*args,**kwargs):
            if mode=='x':self.routed.write_bytes(b'mutation after preflight checks')
            return original(filename,mode,*args,**kwargs)
        with patch.object(exporter.zipfile,'ZipFile',side_effect=open_archive):
            with self.assertRaisesRegex(ValueError,'Payload changed while exporting'):self.export()
        self.assertFalse((self.output/'manifest.json').exists())

    def test_existing_release_is_immutable(self):
        self.export();before=digest(self.output/'manifest.json')
        with self.assertRaisesRegex(ValueError,'existing releases are immutable'):self.export()
        self.assertEqual(digest(self.output/'manifest.json'),before)


if __name__=='__main__':
    print('TRANSPORT_FIXTURES_ONLY',WORK,flush=True)
    unittest.main(verbosity=2)
