"""Tests for client singleton (kill-and-takeover) functionality."""

import os
import signal
import subprocess
import sys
from unittest import mock

import pytest


class TestTakeoverFromOldInstances:
    """Tests for _takeover_from_old_instances() function."""

    def test_no_existing_instances(self):
        """When pgrep finds no matches, function returns without action."""
        from stt_service.client import _takeover_from_old_instances

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=1, stdout=b"")
            _takeover_from_old_instances()

            mock_run.assert_called_once()
            assert "pgrep" in mock_run.call_args[0][0]

    def test_only_current_process_found(self):
        """When pgrep only finds current process, no kill is attempted."""
        from stt_service.client import _takeover_from_old_instances

        current_pid = str(os.getpid())

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout=f"{current_pid}\n".encode()
            )
            with mock.patch("os.kill") as mock_kill:
                _takeover_from_old_instances()
                mock_kill.assert_not_called()

    def test_excludes_parent_process(self):
        """When pgrep finds current and parent process (uv wrapper), no kill is attempted."""
        from stt_service.client import _takeover_from_old_instances

        current_pid = os.getpid()
        parent_pid = os.getppid()

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout=f"{current_pid}\n{parent_pid}\n".encode()
            )
            with mock.patch("os.kill") as mock_kill:
                _takeover_from_old_instances()
                mock_kill.assert_not_called()

    def test_kills_single_other_instance(self):
        """When one other instance exists, sends SIGTERM then checks for exit."""
        from stt_service.client import _takeover_from_old_instances

        current_pid = os.getpid()
        other_pid = 99999  # Fake PID

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout=f"{current_pid}\n{other_pid}\n".encode()
            )
            with mock.patch("os.kill") as mock_kill:
                # First kill(SIGTERM) succeeds, then kill(0) raises ProcessLookupError
                # (meaning process exited gracefully)
                mock_kill.side_effect = [
                    None,  # SIGTERM succeeds
                    ProcessLookupError(),  # Process already dead on check
                ]
                with mock.patch("time.sleep"):
                    _takeover_from_old_instances()

                # Should have called kill twice: SIGTERM, then liveness check
                assert mock_kill.call_count == 2
                mock_kill.assert_any_call(other_pid, signal.SIGTERM)
                mock_kill.assert_any_call(other_pid, 0)

    def test_sigkill_fallback_for_stubborn_process(self):
        """When process survives SIGTERM, sends SIGKILL."""
        from stt_service.client import _takeover_from_old_instances

        current_pid = os.getpid()
        other_pid = 99999

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout=f"{current_pid}\n{other_pid}\n".encode()
            )
            with mock.patch("os.kill") as mock_kill:
                # SIGTERM succeeds, liveness check succeeds (still alive), SIGKILL sent
                mock_kill.side_effect = [
                    None,  # SIGTERM
                    None,  # Liveness check - process still alive
                    None,  # SIGKILL
                ]
                with mock.patch("time.sleep"):
                    _takeover_from_old_instances()

                assert mock_kill.call_count == 3
                mock_kill.assert_any_call(other_pid, signal.SIGTERM)
                mock_kill.assert_any_call(other_pid, 0)
                mock_kill.assert_any_call(other_pid, signal.SIGKILL)

    def test_handles_permission_error(self):
        """When kill fails with PermissionError, logs error and continues."""
        from stt_service.client import _takeover_from_old_instances

        current_pid = os.getpid()
        other_pid = 99999

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0, stdout=f"{current_pid}\n{other_pid}\n".encode()
            )
            with mock.patch("os.kill") as mock_kill:
                mock_kill.side_effect = PermissionError("Operation not permitted")
                with mock.patch("time.sleep"):
                    # Should not raise, just log and continue
                    _takeover_from_old_instances()

    def test_handles_multiple_instances(self):
        """When multiple other instances exist, kills all of them."""
        from stt_service.client import _takeover_from_old_instances

        current_pid = os.getpid()
        other_pids = [99998, 99999]

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(
                returncode=0,
                stdout=f"{current_pid}\n{other_pids[0]}\n{other_pids[1]}\n".encode(),
            )
            with mock.patch("os.kill") as mock_kill:
                # All processes exit gracefully after SIGTERM
                mock_kill.side_effect = [
                    None,  # SIGTERM to first
                    None,  # SIGTERM to second
                    ProcessLookupError(),  # First already dead
                    ProcessLookupError(),  # Second already dead
                ]
                with mock.patch("time.sleep"):
                    _takeover_from_old_instances()

                # Should have sent SIGTERM to both, then checked both
                assert mock_kill.call_count == 4


class TestSetupShutdownHandler:
    """Tests for _setup_shutdown_handler() function."""

    def test_registers_sigterm_handler(self):
        """Shutdown handler is registered for SIGTERM."""
        from stt_service.client import _setup_shutdown_handler

        with mock.patch("signal.signal") as mock_signal:
            _setup_shutdown_handler(None)

            mock_signal.assert_called_once()
            call_args = mock_signal.call_args
            assert call_args[0][0] == signal.SIGTERM
            assert callable(call_args[0][1])

    def test_handler_stops_tray_when_present(self):
        """When tray is provided, handler calls tray.stop()."""
        from stt_service.client import _setup_shutdown_handler

        mock_tray = mock.Mock()
        handler_func = None

        def capture_handler(sig, func):
            nonlocal handler_func
            handler_func = func

        with mock.patch("signal.signal", side_effect=capture_handler):
            _setup_shutdown_handler(mock_tray)

        # Invoke the handler (will call sys.exit, so mock it)
        with mock.patch("sys.exit") as mock_exit:
            handler_func(signal.SIGTERM, None)

            mock_tray.stop.assert_called_once()
            mock_exit.assert_called_once_with(0)

    def test_handler_works_without_tray(self):
        """When tray is None, handler still exits cleanly."""
        from stt_service.client import _setup_shutdown_handler

        handler_func = None

        def capture_handler(sig, func):
            nonlocal handler_func
            handler_func = func

        with mock.patch("signal.signal", side_effect=capture_handler):
            _setup_shutdown_handler(None)

        with mock.patch("sys.exit") as mock_exit:
            handler_func(signal.SIGTERM, None)
            mock_exit.assert_called_once_with(0)
