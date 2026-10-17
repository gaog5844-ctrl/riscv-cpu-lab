"""Negative tests for the commit checker; no RTL/Spike execution required."""
import copy
import csv
from pathlib import Path
import tempfile
import unittest

from spike_reference import compare


class CommitCheckerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'trace.csv'
        self.end = 0x80000008
        self.expected = [
            dict(pc=0x80000000, insn=0x00552023, rd=0, data=0,
                 stores=[(0x80040000, 0x12345678)]),
            dict(pc=0x80000004, insn=0x00052303, rd=6, data=0x12345678,
                 stores=[], load_addr=0x80040000),
        ]
        self.rows = [
            dict(cycle=1, pc=0x80000000, insn=0x00552023, npc=0x80000004,
                 rd=0, data=0, trap=0, cause=0, tval=0,
                 mem_addr=0x80040000, mem_data=0x12345678, mem_wstrb=15),
            dict(cycle=2, pc=0x80000004, insn=0x00052303, npc=self.end,
                 rd=6, data=0x12345678, trap=0, cause=0, tval=0,
                 mem_addr=0x80040000, mem_data=0, mem_wstrb=0),
            dict(cycle=3, pc=self.end, insn=0x00100073, npc=self.end+4,
                 rd=0, data=0, trap=1, cause=3, tval=0,
                 mem_addr=0, mem_data=0, mem_wstrb=0),
        ]

    def tearDown(self):
        self.temp.cleanup()

    def write(self, rows):
        with self.path.open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=self.rows[0])
            writer.writeheader()
            for row in rows:
                writer.writerow({key: str(value) if key == 'cycle' else f'{value:x}'
                                 for key, value in row.items()})

    def test_valid_trace(self):
        self.write(self.rows)
        self.assertEqual(compare(self.path, self.expected, self.end), 2)

    def test_reject_corrupt_trace(self):
        mutations = [
            (0, 'trap', 1), (0, 'mem_wstrb', 1),
            (2, 'rd', 5), (2, 'data', 1), (2, 'mem_wstrb', 15),
            (0, 'pc', 0), (0, 'insn', 0x13), (0, 'npc', self.end),
            (0, 'mem_addr', 0x80040004), (0, 'mem_data', 1),
            (1, 'mem_addr', 0x80040004), (1, 'data', 1),
        ]
        for row, key, value in mutations:
            with self.subTest(row=row, key=key):
                changed = copy.deepcopy(self.rows)
                changed[row][key] = value
                self.write(changed)
                with self.assertRaises(AssertionError):
                    compare(self.path, self.expected, self.end)
        for rows in ([], self.rows[1:], self.rows[:1] + self.rows):
            with self.subTest(length=len(rows)):
                self.write(rows)
                with self.assertRaises(AssertionError):
                    compare(self.path, self.expected, self.end)


if __name__ == '__main__':
    unittest.main()
