defmodule Instabot.Network.SafeUrl do
  @moduledoc false

  @allowed_ports [80, 443]

  def validate(url, resolver \\ &resolve/1) do
    with {:ok, uri} <- validate_structure(url),
         {:ok, addresses} <- resolver.(uri.host),
         true <- addresses != [],
         true <- Enum.all?(addresses, &public_address?/1) do
      {:ok, uri}
    else
      _reason -> {:error, :unsafe_url}
    end
  end

  def validate_structure(url) when is_binary(url) do
    uri = URI.parse(url)
    port = effective_port(uri)

    case uri do
      %URI{scheme: scheme, host: host, userinfo: nil}
      when scheme in ["http", "https"] and is_binary(host) and port in @allowed_ports ->
        {:ok, uri}

      _uri ->
        {:error, :unsafe_url}
    end
  end

  def validate_structure(_url), do: {:error, :unsafe_url}

  def public_address?({first, _second, _third, _fourth}) when first == 0 or first == 10 or first == 127, do: false

  def public_address?({100, second, _third, _fourth}) when second in 64..127, do: false
  def public_address?({169, 254, _third, _fourth}), do: false
  def public_address?({172, second, _third, _fourth}) when second in 16..31, do: false
  def public_address?({192, 0, 0, _fourth}), do: false
  def public_address?({192, 0, 2, _fourth}), do: false
  def public_address?({192, 88, 99, _fourth}), do: false
  def public_address?({192, 168, _third, _fourth}), do: false
  def public_address?({198, second, _third, _fourth}) when second in 18..19, do: false
  def public_address?({198, 51, 100, _fourth}), do: false
  def public_address?({203, 0, 113, _fourth}), do: false
  def public_address?({first, _second, _third, _fourth}) when first >= 224, do: false
  def public_address?({_first, _second, _third, _fourth}), do: true

  def public_address?({first, second, _third, _fourth, _fifth, _sixth, _seventh, _eighth}) do
    first in 0x2000..0x3FFF and not (first == 0x2001 and second == 0x0DB8)
  end

  def public_address?(_address), do: false

  def resolve(host) do
    with {:ok, ipv4_addresses} <- resolve_family(host, :inet),
         {:ok, ipv6_addresses} <- resolve_family(host, :inet6) do
      {:ok, ipv4_addresses ++ ipv6_addresses}
    end
  end

  defp effective_port(%URI{port: port}) when is_integer(port), do: port
  defp effective_port(%URI{scheme: scheme}) when is_binary(scheme), do: URI.default_port(scheme)
  defp effective_port(_uri), do: nil

  defp resolve_family(host, family) do
    case :inet.getaddrs(String.to_charlist(host), family) do
      {:ok, addresses} -> {:ok, addresses}
      {:error, :nxdomain} -> {:ok, []}
      {:error, :eafnosupport} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end
end
