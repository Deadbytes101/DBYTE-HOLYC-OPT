"""R15 release profiles keep historical ISO audit pins immutable."""
import unittest
from tools import check_redsea

R12_NATIVE = "ba1d234e27f9e60242511d20bcfbbd88643d56fbe4d8c2b4ad3c7de52261293a"
R14_NATIVE = "4be1688a2a0a720fe8f168c6603ff57c8f195f7d404ce23a77baac3b6d964abd"
GUEST = "6885186129cd67705801f38aceb9cf93dc23a757c8d3cc0c06675e670d6e4231"


class ReleaseMediaProfiles(unittest.TestCase):
    def test_r12_profile_keeps_original_four_sources(self):
        self.assertEqual(len(check_redsea.EXPECTED_R12), 4)
        self.assertEqual(check_redsea.EXPECTED_R12["DBOPT.HC"][1], R12_NATIVE)
        self.assertNotIn("GUEST.PRJ", check_redsea.EXPECTED_R12)

    def test_r13_profile_keeps_original_five_sources(self):
        self.assertEqual(len(check_redsea.EXPECTED_R13), 5)
        self.assertEqual(check_redsea.EXPECTED_R13["DBOPT.HC"][1], R12_NATIVE)
        self.assertEqual(check_redsea.EXPECTED_R13["GUEST.PRJ"][1], GUEST)

    def test_r15_combined_profile_uses_new_native_and_guest(self):
        self.assertEqual(len(check_redsea.EXPECTED), 5)
        self.assertEqual(check_redsea.EXPECTED["DBOPT.HC"][1], R14_NATIVE)
        self.assertEqual(check_redsea.EXPECTED["GUEST.PRJ"][1], GUEST)


if __name__ == "__main__":
    unittest.main()
