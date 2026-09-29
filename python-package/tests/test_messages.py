import re

import pytest

from geocodebr import messages
from geocodebr.messages import confirm, inform


def test_inform_prints_timestamp_when_verbose(capsys):
    inform("teste", True)
    out = capsys.readouterr().out
    assert re.match(r"\d{2}:\d{2}:\d{2}: teste", out)


def test_inform_silent_when_not_verbose(capsys):
    inform("silencioso", False)
    assert capsys.readouterr().out == ""


def test_confirm_prints_message_without_timestamp(capsys):
    confirm("Cache definido")
    out = capsys.readouterr().out
    assert out.strip() == "Cache definido"
    assert not re.search(r"\d{2}:\d{2}:\d{2}", out)


@pytest.mark.parametrize(
    "func_name",
    sorted(
        name
        for name, obj in vars(messages).items()
        if name.startswith("message_") and callable(obj)
    ),
)
def test_message_functions_print_when_verbose(func_name, capsys):
    getattr(messages, func_name)(True)
    assert capsys.readouterr().out.strip() != ""
