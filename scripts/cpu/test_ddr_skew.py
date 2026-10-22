"""Complete native skew groups must be present and bound to the frozen FDC."""
import io
import unittest
import xml.etree.ElementTree as ET

from review_ddr_board import parse_skew


HEADERS = ['Path','Slack','Logic Levels','High Fanout','Start Point','End Point',
    'Launch Clock','Capture Clock','Clock Skew','Data Delay','Required Skew',
    'Actual Skew','Relative Delay','Relative CPR']


def fixture():
    root = ET.Element('tables')
    lines = []
    pairs = [(channel, source, target) for channel in ['aw','w','b','ar','r']
        for source,target in [('wr_gray','wr_gray_rd_sync1'),('rd_gray','rd_gray_wr_sync1')]]
    for channel, source, target in pairs:
        prefix = 'u_system/u_cdc/u_'+channel+'_fifo/'
        launch = prefix+source+r'\[[0-9:]+\]/Q(\[[0-9]+\])?'
        capture = prefix+target+r'\[[0-9:]+\]/D(\[[0-9]+\])?'
        lines.append('set_max_skew 2.000 -from [get_pins -regexp -hsc / {'+launch+'}] -to [get_pins -regexp -hsc / {'+capture+'}]')
    def data(parent, values):
        for value in values:
            ET.SubElement(parent,'data').text = value
    for corner in ['slow','fast']:
        table = ET.SubElement(root,'table',id='report_timing_'+corner+'_path_max_skew')
        data(ET.SubElement(table,'column_headers'), HEADERS)
        for line,(channel,source,target) in enumerate(pairs,1):
            group = ET.SubElement(table,'row')
            data(group,[f'MaxSkew Path 2.000ns, Line Num {line}','1.700',
                '', '', '', '', '', '', '', '', '2.000','0.300','',''])
            for kind in ['max','min']:
                section = ET.SubElement(group,'row')
                data(section,['skew for '+kind+' path']+['']*13)
                for bit in range(3):
                    path = ET.SubElement(section,'row')
                    prefix = 'u_system/u_cdc/u_'+channel+'_fifo/'
                    data(path,[f'Path {bit+1}','1.700','0','1',
                        prefix+source+f'[{bit}]/opit_0/Q',prefix+target+f'[{bit}]/opit_0/D',
                        '','cpu_clk','4.000','0.500','2.000','0.300','0.500','0.000'])
    return root,'\n'.join(lines)+'\n'


class SkewTests(unittest.TestCase):
    def run_fixture(self, root, fdc):
        return parse_skew(io.StringIO(ET.tostring(root,encoding='unicode')),fdc)

    def test_all_buses_both_corners_and_every_bit(self):
        root,fdc=fixture()
        result=self.run_fixture(root,fdc)
        self.assertTrue(result['met'])
        self.assertEqual(len(result['groups']),20)
        self.assertEqual(result['worst_slack_ns'],1.7)

    def test_missing_corner_is_rejected(self):
        root,fdc=fixture(); root.remove(root.findall('table')[1])
        with self.assertRaises(ValueError): self.run_fixture(root,fdc)

    def test_missing_group_is_rejected(self):
        root,fdc=fixture(); table=root.find('table'); table.remove(table.find('row'))
        with self.assertRaises(ValueError): self.run_fixture(root,fdc)

    def test_missing_bit_is_rejected(self):
        root,fdc=fixture(); section=root.find('table/row/row'); section.remove(section.find('row'))
        with self.assertRaises(ValueError): self.run_fixture(root,fdc)

    def test_wrong_constraint_line_is_rejected(self):
        root,fdc=fixture(); root.find('table/row/data').text='MaxSkew Path 2.000ns, Line Num 12345'
        with self.assertRaises(ValueError): self.run_fixture(root,fdc)

    def test_wrong_synchronizer_stage_is_rejected(self):
        root,fdc=fixture(); endpoint=root.find('table/row/row/row').findall('data')[5]
        endpoint.text=endpoint.text.replace('sync1','sync2')
        with self.assertRaises(ValueError): self.run_fixture(root,fdc)

    def test_actual_violation_is_reported(self):
        root,fdc=fixture(); values=root.find('table/row').findall('data')
        values[1].text='-0.100'; values[11].text='2.100'
        self.assertFalse(self.run_fixture(root,fdc)['met'])

    def test_inconsistent_slack_is_rejected(self):
        root,fdc=fixture(); root.find('table/row').findall('data')[1].text='1.900'
        with self.assertRaises(ValueError): self.run_fixture(root,fdc)


if __name__=='__main__':
    unittest.main()
