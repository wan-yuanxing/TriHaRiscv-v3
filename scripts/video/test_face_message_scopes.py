"""Historical placement routing must not mask current-route diagnostics."""
import tempfile
import unittest
from pathlib import Path

from qualify_face_bitstream import collect_messages


CRITICAL='C: STA-3017: clock cross SRB paths do not meet the required hold violation threshold(200ps).\n'
ERROR='E: Route-9999: deliberate current-route failure.\n'
PLACED='Placement done.\nFinished placement.\n'
ROUTING='Routing started.\n'


class MessageScopes(unittest.TestCase):
    def review(self, old, current='', reused=True, same_file=False):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);placement=root/'place.log';route=root/'route.log'
            placement.write_text(old,encoding='utf-8')
            route.write_text(current,encoding='utf-8')
            if same_file:route=placement
            return collect_messages([placement,route],placement,route,'','avatar',reused)

    def test_old_route_warning_is_recorded_separately(self):
        r=self.review(PLACED+ROUTING+CRITICAL,ROUTING)
        self.assertEqual(r['rejected'],[])
        self.assertEqual(r['unused_historical_route_messages'][0]['messages'],[CRITICAL.strip()])

    def test_old_placement_warning_still_rejected(self):
        r=self.review(CRITICAL+PLACED+ROUTING,ROUTING)
        self.assertEqual(r['rejected'],[CRITICAL.strip()])

    def test_current_route_warning_still_rejected(self):
        r=self.review(PLACED+ROUTING+CRITICAL,ROUTING+CRITICAL)
        self.assertEqual(r['rejected'],[CRITICAL.strip()])

    def test_current_route_error_still_rejected(self):
        r=self.review(PLACED+ROUTING,ROUTING+ERROR)
        self.assertEqual(r['rejected'],[ERROR.strip()])

    def test_same_log_is_never_trimmed(self):
        for reused in (False,True):
            with self.subTest(reused=reused):
                r=self.review(PLACED+ROUTING+CRITICAL,reused=reused,same_file=True)
                self.assertEqual(r['rejected'],[CRITICAL.strip()])

    def test_standalone_placement_keeps_all_messages(self):
        r=self.review(PLACED+CRITICAL,ROUTING)
        self.assertEqual(r['rejected'],[CRITICAL.strip()])

    def test_incomplete_or_ambiguous_phase_boundaries_rejected(self):
        for old in (ROUTING+CRITICAL,PLACED+ROUTING+ROUTING,ROUTING+PLACED,PLACED+PLACED+ROUTING):
            with self.subTest(old=old),self.assertRaises(ValueError):
                self.review(old,ROUTING)


if __name__=='__main__':unittest.main()
