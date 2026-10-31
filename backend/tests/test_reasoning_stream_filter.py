"""Reasoning tags must never reach the user's answer stream."""
from __future__ import annotations

from app.llm import ReasoningFilter, _strip_reasoning_stream


def run(pieces):
    return "".join(_strip_reasoning_stream(iter(pieces)))


def test_empty_think_block_is_dropped():
    assert run(["<think></think>", "## Jawaban"]) == "## Jawaban"


def test_think_block_with_content_is_dropped():
    assert run(["<think>", "internal plan", "</think>", "Hasil: 10"]) == "Hasil: 10"


def test_tag_split_across_chunks_is_dropped():
    assert run(["<th", "ink>", "noise", "</thi", "nk>", "Answer"]) == "Answer"


def test_text_before_and_after_the_block_is_kept():
    assert run(["Intro ", "<think>x</think>", " tail"]) == "Intro  tail"


def test_plain_text_streams_unchanged():
    assert run(["Revenue ", "naik ", "3%"]) == "Revenue naik 3%"


def test_markdown_with_angle_brackets_is_preserved():
    assert run(["nilai < 5 dan > 3"]) == "nilai < 5 dan > 3"


def test_html_like_content_that_is_not_a_reasoning_tag_is_kept():
    assert run(["<b>bold</b> text"]) == "<b>bold</b> text"


def test_reasoning_variants_are_covered():
    assert run(["<thinking>a</thinking>B"]) == "B"
    assert run(["<reasoning>a</reasoning>B"]) == "B"


def test_tag_with_attributes_is_dropped():
    assert run(['<think type="x">a</think>B']) == "B"


def test_unterminated_block_does_not_leak_partial_reasoning():
    assert run(["<think>", "never closed"]) == ""


def test_trailing_bare_angle_bracket_is_real_text():
    # A dangling "<" is not a reasoning tag, so it must still reach the user.
    assert run(["Answer ", "<"]) == "Answer <"


def test_trailing_partial_reasoning_tag_is_dropped():
    assert run(["Answer", "<thi"]) == "Answer"


def test_long_run_after_an_angle_bracket_still_flushes():
    text = "a<" + "x" * 60
    assert run([text]) == text


def test_opener_with_long_attributes_split_across_pieces_does_not_leak():
    # A generous attribute list must not be mistaken for ordinary text.
    pieces = ["<think ", 'data-x="' + "y" * 80 + '"', ">", "secret plan", "</think>", "Answer"]
    assert run(pieces) == "Answer"


def test_closing_tag_never_leaks_when_opener_was_long():
    assert "</think>" not in run(['<think class="' + "a" * 60 + '">x</think>', "Hasil"])


def test_state_survives_a_continuation_boundary():
    # A reasoning block split across two streamed segments (token-cap continuation)
    # must stay suppressed; a fresh filter per segment would leak the tail.
    filt = ReasoningFilter()
    first = "".join(out for p in ["<think>", "half a plan"] for out in filt.feed(p))
    assert filt.inside_block
    second = "".join(out for p in ["rest of plan", "</think>", "Jawaban"]
                     for out in filt.feed(p))
    tail = "".join(filt.flush())
    assert first == ""
    assert second + tail == "Jawaban"


def test_filter_reports_when_it_is_outside_a_block():
    filt = ReasoningFilter()
    list(filt.feed("plain text"))
    assert not filt.inside_block


def test_unclosed_block_flushes_nothing():
    filt = ReasoningFilter()
    list(filt.feed("<think>dangling"))
    assert "".join(filt.flush()) == ""


def test_non_reasoning_tag_prefix_is_emitted_promptly():
    # "<b" cannot become a reasoning tag, so it must not be held back.
    filt = ReasoningFilter()
    assert "".join(filt.feed("text <b")) == "text <b"


def test_non_streaming_chat_also_strips_reasoning(monkeypatch):
    """The advisory answer and the profile compiler use llm.chat, and their text goes
    straight to the user, so the non-streaming path needs the same filter."""
    from app import llm

    monkeypatch.setattr(llm, "_post", lambda *a, **k: object())
    monkeypatch.setattr(llm, "_parse_sse",
                        lambda resp: iter(["<think>", "plan", "</think>", "Jawaban: 10"]))
    assert llm.chat([{"role": "user", "content": "x"}]) == "Jawaban: 10"


def test_non_streaming_chat_preserves_plain_text(monkeypatch):
    from app import llm

    monkeypatch.setattr(llm, "_post", lambda *a, **k: object())
    monkeypatch.setattr(llm, "_parse_sse",
                        lambda resp: iter(["Revenue ", "naik ", "3% (a < b)"]))
    assert llm.chat([{"role": "user", "content": "x"}]) == "Revenue naik 3% (a < b)"
