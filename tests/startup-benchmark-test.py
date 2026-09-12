#!/usr/bin/env python3
"""Validate the benchmark's startup coverage and failure detection."""
import importlib.util
import os
import pathlib
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("startup_benchmark", ROOT / "tests/startup-benchmark.py")
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class StartupBenchmarkTest(unittest.TestCase):
    def setUp(self):
        # The calling agent commonly has both guards set. A first-env fixture
        # must still initialize its own profile and project environment.
        with patch.dict(os.environ, {"_DOTFILES_ENV_LOADED": "1", "_DOTFILES_BASE_ENV": "1", "BASH_ENV": "/missing-agent-profile"}):
            self.fixture = benchmark.Fixture(ROOT)
        self.addCleanup(self.fixture.close)

    def test_every_supported_mode_loads_expected_configuration(self):
        for shell in ("bash", "zsh"):
            for mode in ("first-env", "inherited", "interactive"):
                with self.subTest(shell=shell, mode=mode):
                    self.fixture.sample(shell, mode)
        self.fixture.sample("bash", "snapshot")

    def test_zsh_fpath_is_distribution_owned(self):
        roots = self.fixture.env["FPATH"].split(":")
        self.assertTrue(roots)
        self.assertTrue(
            all(path.startswith(("/usr/share/zsh/", "/usr/lib/zsh/")) for path in roots)
        )
        self.assertTrue(any((pathlib.Path(path) / "compinit").is_file() for path in roots))
        self.assertTrue((self.fixture.root / "home/.zcompdump").is_file())
        self.assertTrue((self.fixture.root / "cache/dotfiles/zsh/completions/_uv").is_file())

    def test_missing_profile_fails_even_with_inherited_guards(self):
        (self.fixture.root / "home/.profile").unlink()
        for shell in ("bash", "zsh"):
            with self.subTest(shell=shell), self.assertRaises(RuntimeError):
                self.fixture.sample(shell, "inherited")

    def test_wrong_checkout_fails(self):
        profile = self.fixture.tree / "entry/profile.sh"
        profile.write_text(profile.read_text() + '\nDOTFILES_DIR=/wrong-checkout\n')
        with self.assertRaises(RuntimeError):
            self.fixture.sample("bash", "first-env")

    def test_diagnostics_fail_even_with_zero_exit_status(self):
        profile = self.fixture.tree / "entry/profile.sh"
        profile.write_text(profile.read_text() + '\nprintf "unexpected startup diagnostic\\n" >&2\n')
        for mode in ("first-env", "interactive"):
            with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                self.fixture.sample("bash", mode)

    def test_disabled_theme_startup(self):
        fixture = benchmark.Fixture(ROOT, theme_enabled=False)
        self.addCleanup(fixture.close)
        for shell in ("bash", "zsh"):
            fixture.sample(shell, "interactive")


if __name__ == "__main__":
    unittest.main()
