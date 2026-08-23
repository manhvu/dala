defmodule Dala.Media.Subtitle do
  @moduledoc """
  Timestamp-synchronized subtitle rendering.

  Supports SRT and WebVTT formats. Subtitles are rendered as GPU overlays
  synchronized with the media clock.

  Architecture:
      Subtitle File → Parser → Cue Timeline → Clock Sync → GPU Overlay

  ## Example

      {:ok, sub} = Dala.Media.Subtitle.load("subtitles.srt")

      # In your screen's handle_info:
      def handle_info({:clock, :tick, %{timestamp_us: ts}}, socket) do
        case Dala.Media.Subtitle.active_cue(sub, ts) do
          nil -> {:noreply, socket}
          cue -> {:noreply, render_subtitle(socket, cue)}
        end
      end
  """

  @type cue :: %{
          id: non_neg_integer(),
          start_ms: non_neg_integer(),
          end_ms: non_neg_integer(),
          text: String.t(),
          style: map()
        }

  @type parse_result :: {:ok, [cue()]} | {:error, term()}

  @doc "Parse SRT content into a list of cues."
  @spec parse_srt(String.t()) :: parse_result()
  def parse_srt(content) when is_binary(content) do
    content
    |> String.split(~r/\r?\n\r?\n/, trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {block, idx}, {:ok, acc} ->
      case parse_srt_block(block, idx) do
        {:ok, cue} -> {:cont, {:ok, [cue | acc]}}
        {:error, reason} -> {:halt, {:error, {idx, reason}}}
      end
    end)
    |> then(fn
      {:ok, cues} -> {:ok, Enum.reverse(cues)}
      error -> error
    end)
  end

  @doc "Parse WebVTT content into a list of cues."
  @spec parse_vtt(String.t()) :: parse_result()
  def parse_vtt(<<"WEBVTT", rest::binary>>) do
    rest
    |> String.split(~r/\r?\n\r?\n/, trim: true)
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {block, idx}, {:ok, acc} ->
      case parse_vtt_block(block, idx) do
        {:ok, cue} -> {:cont, {:ok, [cue | acc]}}
        {:error, _} -> {:cont, {:ok, acc}}
      end
    end)
    |> then(fn {:ok, cues} -> {:ok, Enum.reverse(cues)} end)
  end

  def parse_vtt(_), do: {:error, :invalid_vtt_header}

  @doc "Find the active cue for a given timestamp (in microseconds)."
  @spec active_cue([cue()], non_neg_integer()) :: cue() | nil
  def active_cue(cues, timestamp_us) do
    timestamp_ms = div(timestamp_us, 1000)

    Enum.find(cues, fn cue ->
      timestamp_ms >= cue.start_ms and timestamp_ms <= cue.end_ms
    end)
  end

  @doc "Get all cues that fall within a time range."
  @spec cues_in_range([cue()], non_neg_integer(), non_neg_integer()) :: [cue()]
  def cues_in_range(cues, start_us, end_us) do
    start_ms = div(start_us, 1000)
    end_ms = div(end_us, 1000)

    Enum.filter(cues, fn cue ->
      (cue.start_ms >= start_ms and cue.start_ms <= end_ms) or
        (cue.end_ms >= start_ms and cue.end_ms <= end_ms) or
        (cue.start_ms <= start_ms and cue.end_ms >= end_ms)
    end)
  end

  @doc "Format a cue for GPU overlay rendering."
  @spec to_overlay(cue(), keyword()) :: map()
  def to_overlay(cue, opts \\ []) do
    %{
      type: :text,
      text: cue.text,
      position: Keyword.get(opts, :position, {0, 0}),
      font_size: Keyword.get(opts, :font_size, 24),
      color: Keyword.get(opts, :color, {255, 255, 255, 255}),
      background: Keyword.get(opts, :background, {0, 0, 0, 128}),
      max_width: Keyword.get(opts, :max_width, 600)
    }
  end

  # Private — SRT parsing

  defp parse_srt_block(block, _idx) do
    lines = String.split(block, ~r/\r?\n/, trim: true)

    case lines do
      [id_str, timing | text_lines] ->
        with {id, ""} <- Integer.parse(id_str),
             {:ok, start_ms, end_ms} <- parse_srt_timing(timing) do
          {:ok,
           %{
             id: id,
             start_ms: start_ms,
             end_ms: end_ms,
             text: Enum.join(text_lines, "\n"),
             style: %{}
           }}
        else
          _ -> {:error, :invalid_block}
        end

      _ ->
        {:error, :invalid_block}
    end
  end

  defp parse_srt_timing(timing) do
    case Regex.run(
           ~r/(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})/,
           timing
         ) do
      [_, sh, sm, ss, sms, eh, em, es, ems] ->
        start_ms = to_ms(sh, sm, ss, sms)
        end_ms = to_ms(eh, em, es, ems)
        {:ok, start_ms, end_ms}

      _ ->
        {:error, :invalid_timing}
    end
  end

  defp to_ms(h, m, s, ms) do
    String.to_integer(h) * 3_600_000 +
      String.to_integer(m) * 60_000 +
      String.to_integer(s) * 1_000 +
      String.to_integer(ms)
  end

  # Private — VTT parsing

  defp parse_vtt_block(block, idx) do
    lines = String.split(block, ~r/\r?\n/, trim: true)

    case lines do
      [timing | text_lines] when text_lines != [] ->
        case parse_vtt_timing(timing) do
          {:ok, start_ms, end_ms} ->
            {:ok,
             %{
               id: idx,
               start_ms: start_ms,
               end_ms: end_ms,
               text: Enum.join(text_lines, "\n"),
               style: %{}
             }}

          # WebVTT allows an optional cue identifier line before the timing line
          {:error, _} ->
            case text_lines do
              [timing | text_lines] when text_lines != [] ->
                case parse_vtt_timing(timing) do
                  {:ok, start_ms, end_ms} ->
                    {:ok,
                     %{
                       id: idx,
                       start_ms: start_ms,
                       end_ms: end_ms,
                       text: Enum.join(text_lines, "\n"),
                       style: %{}
                     }}

                  error ->
                    error
                end

              _ ->
                {:error, :invalid_timing}
            end
        end

      _ ->
        {:error, :invalid_block}
    end
  end

  defp parse_vtt_timing(timing) do
    case Regex.run(
           ~r/(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})/,
           timing
         ) do
      [_, sh, sm, ss, sms, eh, em, es, ems] ->
        start_ms = to_ms(sh, sm, ss, sms)
        end_ms = to_ms(eh, em, es, ems)
        {:ok, start_ms, end_ms}

      _ ->
        # Try without hours
        case Regex.run(~r/(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2})\.(\d{3})/, timing) do
          [_, sm, ss, sms, em, es, ems] ->
            start_ms = to_ms("00", sm, ss, sms)
            end_ms = to_ms("00", em, es, ems)
            {:ok, start_ms, end_ms}

          _ ->
            {:error, :invalid_timing}
        end
    end
  end
end
