defmodule Instabot.Encryption do
  @moduledoc """
  AES-256-GCM encryption for sensitive data like Instagram credentials and cookies.
  """

  @aad "InstaBot"
  @iv_size 12
  @tag_size 16

  @doc """
  Encrypts a binary or string value using AES-256-GCM.
  Returns the encrypted value as a single binary: <<iv, tag, ciphertext>>.
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(@iv_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, encryption_key(), iv, plaintext, @aad, true)

    iv <> tag <> ciphertext
  end

  @doc """
  Decrypts a value previously encrypted with `encrypt/1`.
  Returns `{:ok, plaintext}` or `{:error, :decryption_failed}`.
  """
  def decrypt(<<iv::binary-size(@iv_size), tag::binary-size(@tag_size), ciphertext::binary>> = _encrypted) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           encryption_key(),
           iv,
           ciphertext,
           @aad,
           tag,
           false
         ) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :decryption_failed}
    end
  end

  def decrypt(_), do: {:error, :invalid_format}

  @doc """
  Encrypts an Elixir term by first encoding it with `:erlang.term_to_binary/1`.
  """
  def encrypt_term(term) do
    term
    |> :erlang.term_to_binary()
    |> encrypt()
  end

  @doc """
  Decrypts a value and decodes it back to an Elixir term.
  Returns `{:ok, term}` or `{:error, reason}`.
  """
  def decrypt_term(encrypted) do
    case decrypt(encrypted) do
      {:ok, binary} -> {:ok, :erlang.binary_to_term(binary, [:safe])}
      error -> error
    end
  end

  defp encryption_key do
    secret_key_base =
      Application.get_env(:instabot, InstabotWeb.Endpoint)[:secret_key_base]

    :crypto.mac(:hmac, :sha256, secret_key_base, "instabot:credentials_v1")
  end
end
