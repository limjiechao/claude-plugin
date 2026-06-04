# Testing

How to run the repository tests before committing changes.

## Bootstrap Unit Tests

Run the Python unit tests for settings reconciliation:

```bash
python3 -m unittest bootstrap.tests.test_settings_reconcile
```

Run the shell smoke tests for `bootstrap/apply.sh`:

```bash
bash bootstrap/tests/test_apply.sh
```

These tests use temporary directories and `CLAUDE_CONFIG_DIR` fixtures. They do not
write to your real `~/.claude` directory.
