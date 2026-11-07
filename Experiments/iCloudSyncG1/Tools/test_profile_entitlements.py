import unittest
from profile_entitlements import allows_cloudkit, allows_development, allows_container


class ProfileAllowlistTests(unittest.TestCase):
    services = 'com.apple.developer.icloud-services'
    environment = 'com.apple.developer.icloud-container-environment'

    def test_observed_apple_profile(self):
        signed = {self.services: ['CloudKit'], self.environment: 'Development'}
        profile = {self.services: '*', self.environment: ['Production', 'Development']}
        self.assertTrue(allows_cloudkit(signed, profile))
        self.assertTrue(allows_development(signed, profile))

    def test_explicit_cloudkit_allowlist(self):
        for allowed in ['CloudKit', ['CloudKit'], ['CloudKit', 'CloudDocuments'], ['*']]:
            with self.subTest(allowed=allowed):
                self.assertTrue(allows_cloudkit({self.services: ['CloudKit']}, {self.services: allowed}))

    def test_missing_wrong_or_malformed_service_denied(self):
        for allowed in [None, [], '', 'CloudDocuments', 'NotCloudKit', ['Cloud*'], {'CloudKit': True}, [None, '*']]:
            with self.subTest(allowed=allowed):
                self.assertFalse(allows_cloudkit({self.services: ['CloudKit']}, {self.services: allowed}))

    def test_wildcard_never_relaxes_signed_claim(self):
        for claimed in [None, '*', ['*'], 'CloudKit', ['CloudKit', 'CloudDocuments']]:
            with self.subTest(claimed=claimed):
                self.assertFalse(allows_cloudkit({self.services: claimed}, {self.services: '*'}))

    def test_environment_order_does_not_matter(self):
        for allowed in ['Development', ['Development'], ['Development', 'Production'], ['Production', 'Development']]:
            with self.subTest(allowed=allowed):
                self.assertTrue(allows_development({self.environment: 'Development'}, {self.environment: allowed}))

    def test_production_or_missing_environment_denied(self):
        for allowed in [None, [], 'Production', ['Production'], '*', ['*'], 'NotDevelopment', {'Development': True}]:
            with self.subTest(allowed=allowed):
                self.assertFalse(allows_development({self.environment: 'Development'}, {self.environment: allowed}))

    def test_profile_never_relaxes_signed_environment(self):
        for claimed in [None, 'Production', '*', ['Development'], 'development']:
            with self.subTest(claimed=claimed):
                self.assertFalse(allows_development({self.environment: claimed}, {self.environment: ['Production', 'Development']}))

    def test_container_requires_exact_array_membership(self):
        key = 'com.apple.developer.icloud-container-identifiers'
        expected = 'iCloud.com.example.SyncLab'
        signed = {key: [expected]}
        self.assertTrue(allows_container(signed, {key: [expected]}, expected))
        for allowed in [expected, 'prefix-' + expected + '-suffix', ['prefix-' + expected + '-suffix'], [expected, None], ['*'], [], None]:
            with self.subTest(allowed=allowed):
                self.assertFalse(allows_container(signed, {key: allowed}, expected))
        self.assertFalse(allows_container({key: ['*']}, {key: [expected]}, expected))


if __name__ == '__main__':
    unittest.main()
