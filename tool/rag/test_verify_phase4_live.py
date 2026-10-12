import copy
import unittest
from verify_phase4_live import check_query, check_answer


class VerificationTests(unittest.TestCase):
    def test_utf16_span_and_exact_fact(self):
        note = {'id': 'n', 'revision': 2, 'content': '😀 12 tháng 11', 'expectedFacts': ['12 tháng 11']}
        result = {'response': {'status': 'ANSWERED', 'answer': '12 tháng 11 [S1]',
                  'sources': [{'sourceId': 'S1', 'noteId': 'n', 'revision': 2,
                               'startOffset': 3, 'endOffset': 14, 'quote': '12 tháng 11'}]},
                  'usage': [], 'elapsedMs': 1000}
        check_query(result, 'ANSWERED', note)
        changed = copy.deepcopy(result)
        changed['response']['sources'][0]['revision'] = 3
        with self.assertRaises(AssertionError):
            check_query(changed, 'ANSWERED', note)

    def test_abstention_never_generates(self):
        result = {'response': {'status': 'NOT_ENOUGH_CONTEXT', 'answer': None, 'sources': []},
                  'usage': [{'model': 'jev-1.13.0'}], 'elapsedMs': 1000}
        check_query(result, 'NOT_ENOUGH_CONTEXT')
        result['usage'].append({'model': 'deepseek-flash'})
        with self.assertRaises(AssertionError):
            check_query(result, 'NOT_ENOUGH_CONTEXT')

    def test_answer_requires_frozen_source_and_inline_citation(self):
        source = {'sourceId': 'S1', 'quote': 'fact'}
        fixture = {'evidence': {'sources': [source]}}
        result = {'status': 'ANSWERED', 'answer': 'fact [S1]', 'sources': [source], 'elapsedMs': 1000}
        check_answer(result, fixture)
        result['answer'] = 'fact'
        with self.assertRaises(AssertionError):
            check_answer(result, fixture)
        result['answer'] = 'fact [S1]'
        result['sources'] = []
        with self.assertRaises(AssertionError):
            check_answer(result, fixture)


if __name__ == '__main__':
    unittest.main()
