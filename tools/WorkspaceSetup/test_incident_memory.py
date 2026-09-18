import json
from pathlib import Path
import tempfile
import unittest

import incident_memory as memory


class IncidentMemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'operations').mkdir()
        (self.root / 'operations/current-state.md').write_text('test vault')
        self.event = dict(version=1, incident_id='sortie-stop', event_id='report-1',
                          title='Repeated disengagement', occurred_at='2026-09-15T01:00:00Z',
                          kind='operator_report', evidence_level='reported', summary='Weapons lower repeatedly.',
                          scope='Historical run; cause not yet established.', tags=['sortie'],
                          evidence=[dict(type='thread', locator='thread-id/turn-id')])

    def test_retry_is_idempotent_but_rewriting_history_fails(self):
        path = memory.record(self.root, self.event)
        before = path.read_bytes()
        memory.record(self.root, self.event)
        self.assertEqual(before, path.read_bytes())
        changed = dict(self.event, summary='Everything worked.')
        with self.assertRaisesRegex(ValueError, 'different content'):
            memory.record(self.root, changed)
        self.assertEqual(before, path.read_bytes())

    def test_test_pass_does_not_erase_live_failure(self):
        memory.record(self.root, self.event)
        second = dict(self.event, event_id='test-2', kind='test_passed', evidence_level='simulated',
                      occurred_at='2026-09-15T02:00:00Z', summary='Synthetic target switch passes.',
                      evidence=[dict(type='test', locator='test.log', sha256='a'*64)])
        memory.record(self.root, second)
        report = (self.root / 'operations/incidents/sortie-stop.md').read_text(encoding='utf-8')
        self.assertIn('Weapons lower repeatedly.', report)
        self.assertIn('Synthetic target switch passes.', report)
        self.assertIn('no automatic resolved status', report)
        with self.assertRaisesRegex(ValueError, 'live evidence'):
            memory.validate(dict(second, kind='live_passed'))

    def test_corrections_require_existing_same_incident_reference(self):
        memory.record(self.root, self.event)
        correction = dict(self.event, event_id='correction-2', supersedes=['missing'])
        with self.assertRaisesRegex(ValueError, 'does not exist'):
            memory.record(self.root, correction)
        correction['supersedes'] = ['report-1']
        memory.record(self.root, correction)
        self.assertEqual(len(memory.load_events(self.root)), 2)

    def test_evidence_and_safe_identifiers_are_required(self):
        for change in ({'incident_id': '../escape'}, {'event_id': 'x/y'}, {'evidence': []},
                       {'occurred_at': '2026-09-15T01:00:00'}, {'kind': 'resolved'}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                memory.validate(dict(self.event, **change))
        with self.assertRaisesRegex(ValueError, 'hashed test evidence'):
            memory.validate(dict(self.event, kind='test_passed', evidence_level='simulated'))

    def test_writer_conflict_preserves_first_writer_lock(self):
        base = self.root / 'operations/incidents'
        base.mkdir()
        lock = base / '.writer.lock'
        lock.write_text('existing writer')
        with self.assertRaises(FileExistsError):
            memory.record(self.root, self.event)
        self.assertEqual(lock.read_text(), 'existing writer')

    def test_hashes_and_diagnostic_counts_never_become_success(self):
        path = self.root / 'diagnostic.json'
        data = dict(kind='partyops-historical-diagnostic', version=1,
                    requested_window=dict(started_at='2026-09-15T01:00:00Z', ended_at='2026-09-15T01:01:00Z'),
                    observers=[dict(character='Example', selected_records=0, result='no-records-in-window')])
        path.write_text(json.dumps(data))
        event = memory.diagnostic_event(path, 'sortie-stop', 'Sortie')
        self.assertEqual(event['kind'], 'limitation')
        self.assertIn('0 records', event['summary'])
        self.assertEqual(event['evidence'][0]['sha256'], memory.digest(path.read_bytes()))
        memory.record(self.root, event)
        data['kind'] = 'invented-parser'
        path.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            memory.diagnostic_event(path, 'sortie-stop', 'Sortie')


if __name__ == '__main__':
    unittest.main()
