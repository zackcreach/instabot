defmodule Instabot.TurnstileTest do
  use ExUnit.Case, async: false

  alias Instabot.Turnstile

  setup do
    previous_config = Application.get_env(:instabot, :turnstile)

    on_exit(fn ->
      Application.put_env(:instabot, :turnstile, previous_config)
    end)
  end

  test "bypasses verification when disabled" do
    Application.put_env(:instabot, :turnstile, enabled: false)

    assert :ok == Turnstile.verify(nil)
  end

  test "rejects a missing response when enabled" do
    Application.put_env(:instabot, :turnstile, enabled: true, secret_key: "secret")

    assert {:error, :verification_failed} == Turnstile.verify(nil)
  end

  test "rejects a failed Cloudflare response" do
    Req.Test.stub(Turnstile, fn conn ->
      Req.Test.json(conn, %{"success" => false})
    end)

    Application.put_env(:instabot, :turnstile,
      enabled: true,
      secret_key: "secret",
      request_options: [plug: {Req.Test, Turnstile}]
    )

    assert {:error, :verification_failed} == Turnstile.verify("response")
  end

  test "accepts a valid Cloudflare response" do
    Req.Test.stub(Turnstile, fn conn ->
      Req.Test.json(conn, %{"success" => true})
    end)

    Application.put_env(:instabot, :turnstile,
      enabled: true,
      secret_key: "secret",
      request_options: [plug: {Req.Test, Turnstile}]
    )

    assert :ok == Turnstile.verify("response")
  end
end
