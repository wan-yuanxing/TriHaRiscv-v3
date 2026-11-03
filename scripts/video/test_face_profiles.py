"""Reject mixed profiles, missing modes/assets and missing physical mode key."""
import copy
import unittest
from face_profiles import PROFILES, require_profile, require_simulation_profile
from qualify_face_bitstream import check_sites


class ProfileTests(unittest.TestCase):
    def test_exact_profiles(self):
        for name, params in PROFILES.items():
            build = dict(face_profile=name, top_parameters=dict(params))
            self.assertEqual(require_profile(build), name)
            for key in params:
                bad = copy.deepcopy(build); bad['top_parameters'][key] ^= 1
                with self.assertRaises(ValueError): require_profile(bad)

    def test_real_avatar_modes(self):
        result = dict(avatar_boot=True, boot_load=True, model_preloaded=False, expected_faces=1,
                      avatar_oracle=dict(covered_pixels=100, changed_pixels=80))
        log = '# FACE_SYSTEM_PASS full_pixel_frames=2 modes=111\n'
        require_simulation_profile(result, 'avatar', log)
        for field, value in [('avatar_boot', False), ('boot_load', False), ('model_preloaded', True)]:
            bad = dict(result); bad[field] = value
            with self.assertRaises(ValueError): require_simulation_profile(bad, 'avatar', log)
        with self.assertRaises(ValueError): require_simulation_profile(result, 'avatar', log.replace('111', '010'))
        with self.assertRaises(ValueError): require_simulation_profile(result, 'avatar', log + log)
        bad = dict(result, avatar_oracle=dict(covered_pixels=100, changed_pixels=0))
        with self.assertRaises(ValueError): require_simulation_profile(bad, 'avatar', log)

    def test_empty_scene(self):
        result = dict(avatar_boot=True, boot_load=True, model_preloaded=False, expected_faces=0,
                      avatar_oracle=dict(covered_pixels=0, changed_pixels=0))
        log = '# FACE_SYSTEM_PASS modes=111\n'
        require_simulation_profile(result, 'avatar', log)
        result['avatar_oracle']['covered_pixels'] = 1
        with self.assertRaises(ValueError): require_simulation_profile(result, 'avatar', log)

    def test_physical_key(self):
        ports = 'def_port {mode_button_n} LOC=C23\ndef_port {uart_rx} LOC=B24\n'
        gates = ''.join('def_inst_site {g_full.impl/I_ips_ddr_top/u_ddrphy_top/ddrphy_reset_ctrl/'
                        f'ddrphy_ioclk_gate[{i}]/opit_0_inv}} {site} FF3\n'
                        for i, site in [(0, 'CLMA_357_354'), (1, 'CLMA_357_660')])
        avatar = ports + gates
        box = avatar.replace('def_port {mode_button_n} LOC=C23\n', '')
        check_sites(ports, avatar, 'avatar'); check_sites(ports, box, 'box')
        with self.assertRaises(ValueError): check_sites(ports, box, 'avatar')
        with self.assertRaises(ValueError): check_sites(ports, avatar, 'box')
        with self.assertRaises(ValueError): check_sites(ports, avatar.replace('LOC=C23', 'LOC=C24'), 'avatar')


if __name__ == '__main__': unittest.main()
