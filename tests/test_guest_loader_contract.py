"""R18 check native loader source provenance, distinct from VM execution."""
import os
import unittest
from pathlib import Path

from tools.check_redsea import AuditError
from tools.guest_loader_contract import CONTRACT, inspect_sources, verify


class PinnedNativeLoaderSourceTests(unittest.TestCase):
    def test_loader_source_exact_commit(self):
        upstream = os.environ.get("DBOPT_UPSTREAM")
        if not upstream:
            self.skipTest("set DBOPT_UPSTREAM to the pinned TempleOS archive checkout")
        result = verify(Path(upstream))
        self.assertEqual(result["native_loader_source"], "STATIC_CONTRACT_VERIFIED")
        self.assertEqual(len(result["source_sha256"]), 3)
        self.assertEqual(result["native_loader_execution"], "UNVERIFIED")
        self.assertEqual(result["guest_compilation"], "UNVERIFIED")

    def test_missing_loader_body_is_rejected(self):
        with self.assertRaises(AuditError):
            inspect_sources({name: b"" for name in CONTRACT})

    def test_extra_loader_source_is_rejected(self):
        source = {name: b"" for name in CONTRACT}
        source["Compiler/Injected.HC"] = b"#include"
        with self.assertRaises(AuditError):
            inspect_sources(source)


if __name__ == "__main__":
    unittest.main()
