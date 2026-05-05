defmodule Instabot.Shops.ChangeDetector do
  @moduledoc false

  def detect(nil, snapshot) do
    [
      %{
        change_type: "first_snapshot",
        summary: "Initial Shopify snapshot captured.",
        metadata: snapshot_metadata(snapshot)
      }
    ]
  end

  def detect(previous, snapshot) do
    []
    |> maybe_add(screenshot_changed?(previous, snapshot), screenshot_change(previous, snapshot))
    |> maybe_add(sale_started?(previous, snapshot), sale_started_change(snapshot))
    |> maybe_add(sale_ended?(previous, snapshot), sale_ended_change(previous))
    |> maybe_add(banner_changed?(previous, snapshot), banner_change(previous, snapshot))
    |> maybe_add(price_changed?(previous, snapshot), price_change(previous, snapshot))
    |> maybe_add(compare_at_price_changed?(previous, snapshot), compare_at_price_change(previous, snapshot))
    |> maybe_add(availability_changed?(previous, snapshot), availability_change(previous, snapshot))
    |> Enum.reverse()
  end

  def sale_banner?(text) when is_binary(text) do
    Regex.match?(~r/\b(sale|off|discount|clearance|promo|deal|free shipping|limited time|markdown)\b/i, text)
  end

  def sale_banner?(_text), do: false

  defp maybe_add(changes, true, change), do: [change | changes]
  defp maybe_add(changes, _condition, _change), do: changes

  defp screenshot_changed?(previous, snapshot), do: previous.screenshot_sha256 != snapshot.screenshot_sha256

  defp sale_started?(previous, snapshot) do
    previous.banner_sale_detected == false and snapshot.banner_sale_detected == true
  end

  defp sale_ended?(previous, snapshot) do
    previous.banner_sale_detected == true and snapshot.banner_sale_detected == false
  end

  defp banner_changed?(previous, snapshot) do
    normalize_text(previous.banner_text) != normalize_text(snapshot.banner_text)
  end

  defp price_changed?(previous, snapshot) do
    present_changed?(previous.product_price_cents, snapshot.product_price_cents)
  end

  defp compare_at_price_changed?(previous, snapshot) do
    present_changed?(previous.product_compare_at_price_cents, snapshot.product_compare_at_price_cents)
  end

  defp availability_changed?(previous, snapshot) do
    not is_nil(previous.product_available) and not is_nil(snapshot.product_available) and
      previous.product_available != snapshot.product_available
  end

  defp present_changed?(previous, current) do
    not is_nil(previous) and not is_nil(current) and previous != current
  end

  defp screenshot_change(previous, snapshot) do
    %{
      change_type: "screenshot_changed",
      summary: "Homepage screenshot changed.",
      metadata: %{
        previous_sha256: previous.screenshot_sha256,
        current_sha256: snapshot.screenshot_sha256
      }
    }
  end

  defp sale_started_change(snapshot) do
    %{
      change_type: "sale_banner_started",
      summary: "Sale banner detected: #{truncate(snapshot.banner_text)}",
      metadata: %{banner_text: snapshot.banner_text}
    }
  end

  defp sale_ended_change(previous) do
    %{
      change_type: "sale_banner_ended",
      summary: "Previous sale banner no longer appears.",
      metadata: %{previous_banner_text: previous.banner_text}
    }
  end

  defp banner_change(previous, snapshot) do
    %{
      change_type: "banner_text_changed",
      summary: "Top banner text changed.",
      metadata: %{previous_banner_text: previous.banner_text, current_banner_text: snapshot.banner_text}
    }
  end

  defp price_change(previous, snapshot) do
    %{
      change_type: "product_price_changed",
      summary:
        "Product price changed from #{format_price(previous.product_price_cents, previous.product_currency)} to #{format_price(snapshot.product_price_cents, snapshot.product_currency)}.",
      metadata: %{previous_price_cents: previous.product_price_cents, current_price_cents: snapshot.product_price_cents}
    }
  end

  defp compare_at_price_change(previous, snapshot) do
    %{
      change_type: "product_compare_at_price_changed",
      summary: "Product compare-at price changed.",
      metadata: %{
        previous_compare_at_price_cents: previous.product_compare_at_price_cents,
        current_compare_at_price_cents: snapshot.product_compare_at_price_cents
      }
    }
  end

  defp availability_change(previous, snapshot) do
    %{
      change_type: "product_availability_changed",
      summary: "Product availability changed to #{availability_label(snapshot.product_available)}.",
      metadata: %{previous_available: previous.product_available, current_available: snapshot.product_available}
    }
  end

  defp snapshot_metadata(snapshot) do
    %{
      screenshot_sha256: snapshot.screenshot_sha256,
      banner_sale_detected: snapshot.banner_sale_detected,
      product_price_cents: snapshot.product_price_cents
    }
  end

  defp normalize_text(nil), do: ""

  defp normalize_text(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp truncate(nil), do: "no text"
  defp truncate(text) when byte_size(text) <= 120, do: text
  defp truncate(text), do: String.slice(text, 0, 117) <> "..."

  defp format_price(nil, _currency), do: "unknown"
  defp format_price(cents, nil), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  defp format_price(cents, currency), do: "#{currency} #{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp availability_label(true), do: "available"
  defp availability_label(false), do: "unavailable"
  defp availability_label(_value), do: "unknown"
end
