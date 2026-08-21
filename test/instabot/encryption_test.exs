defmodule Instabot.EncryptionTest do
  use ExUnit.Case, async: true

  alias Instabot.Encryption

  @aad "InstaBot"

  test "encrypts with the dedicated versioned key" do
    encrypted = Encryption.encrypt("sensitive session")

    assert "instabot:v1:" <> _payload = encrypted
    assert {:ok, "sensitive session"} == Encryption.decrypt(encrypted)
  end

  test "decrypts ciphertext created with the legacy derived key" do
    plaintext = :erlang.term_to_binary(%{"cookies" => []})
    legacy_ciphertext = legacy_encrypt(plaintext)

    assert {:ok, %{"cookies" => []}} == Encryption.decrypt_term(legacy_ciphertext)
  end

  defp legacy_encrypt(plaintext) do
    secret_key_base = InstabotWeb.Endpoint.config(:secret_key_base)
    key = :crypto.mac(:hmac, :sha256, secret_key_base, "instabot:credentials_v1")
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)
    iv <> tag <> ciphertext
  end
end
