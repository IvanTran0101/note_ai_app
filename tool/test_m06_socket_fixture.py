"""Local protocol fixture regressions; synthetic actors and sockets only."""
import json
import unittest

import m06_socket_fixture as fixture


class Connection:
    def __init__(self, fail=False):
        self.fail = fail
        self.frames = []

    def send(self, frame):
        if self.fail:
            raise ConnectionError('closed')
        self.frames.append(json.loads(frame))


class SocketFixtureTest(unittest.TestCase):
    def setUp(self):
        fixture.CLIENTS.clear()
        self.addCleanup(fixture.CLIENTS.clear)

    def test_one_actor_receives_on_both_devices_with_independent_ids(self):
        browser, android = Connection(), Connection()
        fixture.subscribe('actor', browser, 'web')
        fixture.subscribe('actor', android, 'native')
        fixture.publish('actor', {'revision': 2})
        self.assertEqual(browser.frames[0]['id'], 'web')
        self.assertEqual(android.frames[0]['id'], 'native')
        self.assertEqual(browser.frames[0]['event'], android.frames[0]['event'])

    def test_disconnecting_one_device_keeps_the_other_subscribed(self):
        browser, android = Connection(), Connection()
        fixture.subscribe('actor', browser, 'web')
        fixture.subscribe('actor', android, 'native')
        fixture.unsubscribe('actor', browser)
        fixture.publish('actor', {'revision': 3})
        self.assertEqual(browser.frames, [])
        self.assertEqual(len(android.frames), 1)

    def test_dead_device_does_not_block_another_actor_or_device(self):
        dead, live, other = Connection(True), Connection(), Connection()
        fixture.subscribe('actor', dead, 'dead')
        fixture.subscribe('actor', live, 'live')
        fixture.subscribe('other', other, 'other')
        fixture.publish('actor', {'revision': 4})
        self.assertEqual(len(live.frames), 1)
        self.assertEqual(other.frames, [])
        self.assertNotIn(dead, dict(fixture.clients_for('actor')))


if __name__ == '__main__':
    unittest.main()
