defmodule Dala.Media.SubtitleTest do
  use ExUnit.Case, async: true

  alias Dala.Media.Subtitle

  @srt """
  1
  00:00:01,000 --> 00:00:03,500
  Hello world

  2
  00:00:04,000 --> 00:00:06,000
  Second cue
  Line two
  """

  @vtt """
  WEBVTT

  00:00:01.000 --> 00:00:03.500
  Hello world

  short
  00:05.000 --> 00:07.250
  No hours here
  """

  describe "parse_srt/1" do
    test "parses cues with timing and text" do
      assert {:ok,
              [
                %{id: 1, start_ms: 1_000, end_ms: 3_500, text: "Hello world", style: %{}},
                %{id: 2, start_ms: 4_000, end_ms: 6_000}
              ]} = Subtitle.parse_srt(@srt)
    end

    test "joins multi-line text with newlines" do
      assert {:ok, [_, %{text: "Second cue\nLine two"}]} = Subtitle.parse_srt(@srt)
    end

    test "handles CRLF line endings" do
      crlf = String.replace(@srt, "\n", "\r\n")
      assert {:ok, [%{text: "Hello world"}, _]} = Subtitle.parse_srt(crlf)
    end

    test "returns error with block index on invalid content" do
      assert {:error, {1, :invalid_block}} =
               Subtitle.parse_srt("1\n00:00:01,000 --> bad\nHello")
    end
  end

  describe "parse_vtt/1" do
    test "rejects content without WEBVTT header" do
      assert {:error, :invalid_vtt_header} = Subtitle.parse_vtt(@srt)
    end

    test "parses full-time cues" do
      assert {:ok,
              [
                %{start_ms: 1_000, end_ms: 3_500, text: "Hello world", style: %{}},
                %{start_ms: 5_000, end_ms: 7_250}
              ]} = Subtitle.parse_vtt(@vtt)
    end

    test "parses hour-less timestamps" do
      assert {:ok, [_, %{start_ms: 5_000, end_ms: 7_250}]} = Subtitle.parse_vtt(@vtt)
    end
  end

  describe "active_cue/2" do
    test "finds the cue containing the timestamp" do
      {:ok, cues} = Subtitle.parse_srt(@srt)
      assert %{id: 1} = Subtitle.active_cue(cues, 2_000_000)
    end

    test "matches inclusive boundaries" do
      {:ok, cues} = Subtitle.parse_srt(@srt)
      assert %{id: 1} = Subtitle.active_cue(cues, 1_000_000)
      assert %{id: 1} = Subtitle.active_cue(cues, 3_500_000)
    end

    test "returns nil between cues and before first" do
      {:ok, cues} = Subtitle.parse_srt(@srt)
      assert nil == Subtitle.active_cue(cues, 3_750_000)
      assert nil == Subtitle.active_cue(cues, 0)
    end
  end

  describe "cues_in_range/3" do
    test "includes cues starting inside the range" do
      {:ok, cues} = Subtitle.parse_srt(@srt)
      assert [%{id: 2}] = Subtitle.cues_in_range(cues, 3_600_000, 5_000_000)
    end

    test "includes cues overlapping the range start" do
      {:ok, cues} = Subtitle.parse_srt(@srt)
      assert [%{id: 1}] = Subtitle.cues_in_range(cues, 2_000_000, 2_500_000)
    end

    test "includes cues spanning the whole range" do
      long = [%{id: 1, start_ms: 0, end_ms: 10_000, text: "long", style: %{}}]
      assert [%{id: 1}] = Subtitle.cues_in_range(long, 4_000_000, 6_000_000)
    end
  end

  describe "to_overlay/2" do
    test "builds an overlay map from a cue" do
      cue = %{id: 1, start_ms: 0, end_ms: 1_000, text: "Hi", style: %{}}

      assert %{
               type: :text,
               text: "Hi",
               position: {0, 0},
               font_size: 24,
               color: {255, 255, 255, 255},
               background: {0, 0, 0, 128},
               max_width: 600
             } = Subtitle.to_overlay(cue)
    end

    test "accepts overrides" do
      cue = %{id: 1, start_ms: 0, end_ms: 1_000, text: "Hi", style: %{}}

      overlay = Subtitle.to_overlay(cue, position: {10, 20}, font_size: 48, color: :yellow)

      assert overlay.position == {10, 20}
      assert overlay.font_size == 48
      assert overlay.color == :yellow
    end
  end
end
