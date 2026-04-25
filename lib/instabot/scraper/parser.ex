defmodule Instabot.Scraper.Parser do
  @moduledoc """
  DOM parsing utilities for extracting structured data from Instagram HTML.
  Pure functions — no side effects, no GenServer state.
  """

  @hashtag_regex ~r/#(\w+)/
  @post_shortcode_regex ~r|/p/([A-Za-z0-9_-]+)/|
  @reel_shortcode_regex ~r|/reel/([A-Za-z0-9_-]+)/|
  @caption_date_regex ~r/\bon\s+([A-Z][a-z]+)\s+(\d{1,2}),\s+(\d{4})\s*:/
  @month_numbers %{
    "January" => 1,
    "February" => 2,
    "March" => 3,
    "April" => 4,
    "May" => 5,
    "June" => 6,
    "July" => 7,
    "August" => 8,
    "September" => 9,
    "October" => 10,
    "November" => 11,
    "December" => 12
  }

  @login_indicators [
    "/accounts/login/",
    "Log in to Instagram",
    "loginForm"
  ]

  @two_factor_indicators [
    "security code",
    "two-factor",
    "verification code",
    "enter the code",
    "confirmationcode",
    "twofactorform",
    "confirm your identity"
  ]

  @login_error_patterns [
    {"sorry, your password was incorrect", :incorrect_password},
    {"please wait a few minutes", :rate_limited},
    {"suspicious login attempt", :suspicious_attempt},
    {"the username you entered doesn't belong", :username_not_found},
    {"challenge_required", :challenge_required},
    {"checkpoint_required", :checkpoint_required}
  ]

  @logged_in_indicators [
    "save your login info",
    "savelogininfo",
    "log out",
    "logout"
  ]

  @doc """
  Extracts post shortcodes and permalinks from a profile page's HTML content.
  Returns a list of maps with `:instagram_post_id` and `:permalink`.
  """
  @spec extract_posts_from_profile(String.t()) :: [map()]
  def extract_posts_from_profile(html) do
    post_shortcodes = Regex.scan(@post_shortcode_regex, html)
    reel_shortcodes = Regex.scan(@reel_shortcode_regex, html)

    all_shortcodes =
      (post_shortcodes ++ reel_shortcodes)
      |> Enum.map(fn [full_match, shortcode] -> {shortcode, full_match} end)
      |> Enum.uniq_by(fn {shortcode, _} -> shortcode end)

    Enum.map(all_shortcodes, fn {shortcode, path} ->
      %{
        instagram_post_id: shortcode,
        permalink: "https://www.instagram.com#{path}"
      }
    end)
  end

  @doc """
  Extracts detailed post data from an individual post page's HTML content.
  Attempts JSON-LD extraction first, then falls back to meta tag extraction.
  Returns a map with `:caption`, `:hashtags`, `:posted_at`, `:post_type`, `:media_urls`.
  """
  @spec extract_post_details(String.t()) :: map()
  def extract_post_details(html) do
    json_ld_data = extract_json_ld(html)
    meta_data = extract_meta_tags(html)
    additional_data = extract_additional_data(html)

    raw_caption =
      get_first_present([
        get_in(json_ld_data, ["articleBody"]),
        get_in(json_ld_data, ["caption", "text"]),
        get_in(additional_data, ["caption"]),
        meta_data["description"]
      ])

    caption = decode_html_entities(raw_caption)
    media_urls = extract_media_urls(html, json_ld_data, additional_data)

    %{
      caption: caption || "",
      hashtags: extract_hashtags(caption || ""),
      posted_at: extract_posted_at(json_ld_data, additional_data) || extract_caption_date(caption || ""),
      post_type: determine_post_type(media_urls, html),
      media_urls: media_urls
    }
  end

  @doc """
  Extracts detailed post data from captured JSON network responses.
  """
  @spec extract_post_details_from_responses([map()], String.t()) :: map() | nil
  def extract_post_details_from_responses(responses, shortcode) when is_list(responses) and is_binary(shortcode) do
    responses
    |> Enum.flat_map(fn
      %{"body" => body} -> collect_post_items(body, shortcode)
      %{body: body} -> collect_post_items(body, shortcode)
      body -> collect_post_items(body, shortcode)
    end)
    |> List.first()
    |> case do
      nil -> nil
      item -> post_details_from_item(item)
    end
  end

  def extract_post_details_from_responses(_responses, _shortcode), do: nil

  @doc """
  Extracts profile metadata from an Instagram profile page.
  """
  @spec extract_profile_metadata(String.t()) :: map()
  def extract_profile_metadata(html) when is_binary(html) do
    meta_data = extract_meta_tags(html)

    %{
      display_name: extract_profile_display_name(html),
      profile_pic_url: decode_html_entities(meta_data["image"])
    }
  end

  def extract_profile_metadata(_), do: %{display_name: nil, profile_pic_url: nil}

  @doc """
  Extracts story data from JS-evaluated story metadata.
  Expects a list of maps from `browser.evaluate()` calls.
  Returns a list of maps with `:instagram_story_id`, `:story_type`, `:media_url`,
  `:posted_at`, `:expires_at`.
  """
  @spec extract_stories([map()]) :: [map()]
  def extract_stories(story_items) when is_list(story_items) do
    Enum.map(story_items, fn item ->
      %{
        instagram_story_id: item["id"] || item["pk"] || generate_story_id(),
        story_type: classify_story_type(item),
        media_url: extract_story_media_url(item),
        posted_at: parse_timestamp(item["taken_at"] || item["taken_at_timestamp"]),
        expires_at: parse_timestamp(item["expiring_at"] || item["expiring_at_timestamp"])
      }
    end)
  end

  def extract_stories(_), do: []

  @doc """
  Extracts story data from captured JSON network responses.
  """
  @spec extract_stories_from_responses([map()]) :: [map()]
  def extract_stories_from_responses(responses) when is_list(responses) do
    responses
    |> Enum.flat_map(fn
      %{"body" => body} -> collect_story_items(body)
      %{body: body} -> collect_story_items(body)
      body -> collect_story_items(body)
    end)
    |> Enum.uniq_by(fn item -> item["id"] || item["pk"] || extract_story_media_url(item) end)
    |> extract_stories()
  end

  def extract_stories_from_responses(_), do: []

  @doc """
  Extracts hashtags from a caption string.
  Returns a list of lowercase hashtag strings without the '#' prefix.
  """
  @spec extract_hashtags(String.t()) :: [String.t()]
  def extract_hashtags(caption) when is_binary(caption) do
    @hashtag_regex
    |> Regex.scan(caption)
    |> Enum.map(fn [_full, tag] -> String.downcase(tag) end)
    |> Enum.uniq()
  end

  def extract_hashtags(_), do: []

  @doc """
  Determines the post type from media URLs and page HTML.
  Returns one of \"image\", \"video\", \"carousel\", \"reel\".
  """
  @spec determine_post_type([String.t()], String.t()) :: String.t()
  def determine_post_type(media_urls, html) do
    cond do
      String.contains?(html, "/reel/") -> "reel"
      length(media_urls) > 1 -> "carousel"
      has_video_indicator?(html) -> "video"
      true -> "image"
    end
  end

  @doc """
  Checks whether the page HTML indicates an Instagram login page (session expired).
  """
  @spec login_page?(String.t()) :: boolean()
  def login_page?(html) when is_binary(html) do
    Enum.any?(@login_indicators, &String.contains?(html, &1))
  end

  def login_page?(_), do: false

  @doc """
  Checks whether the page HTML indicates an Instagram two-factor authentication challenge.
  """
  @spec two_factor_page?(String.t()) :: boolean()
  def two_factor_page?(html) when is_binary(html) do
    html_lower = String.downcase(html)
    Enum.any?(@two_factor_indicators, &String.contains?(html_lower, &1))
  end

  def two_factor_page?(_), do: false

  @doc """
  Checks whether the page HTML contains a login error message.
  Returns `:ok` if no error is detected, or `{:error, reason}` with a specific error atom.
  """
  @spec login_error?(String.t()) :: :ok | {:error, atom()}
  def login_error?(html) when is_binary(html) do
    html_lower = String.downcase(html)

    Enum.find_value(@login_error_patterns, :ok, fn {pattern, reason} ->
      if String.contains?(html_lower, pattern), do: {:error, reason}
    end)
  end

  def login_error?(_), do: :ok

  @doc """
  Checks whether the page HTML indicates a successfully authenticated Instagram session.
  Detects post-login dialogs (e.g. "Save your login info?") and logout links that
  only appear after a successful login.
  """
  @spec logged_in_page?(String.t()) :: boolean()
  def logged_in_page?(html) when is_binary(html) do
    html_lower = String.downcase(html)
    Enum.any?(@logged_in_indicators, &String.contains?(html_lower, &1))
  end

  def logged_in_page?(_), do: false

  # --- Private Helpers ---

  defp extract_json_ld(html) do
    case Regex.run(~r/<script type="application\/ld\+json"[^>]*>(.*?)<\/script>/s, html) do
      [_, json_string] ->
        case Jason.decode(json_string) do
          {:ok, data} -> data
          {:error, _} -> %{}
        end

      _ ->
        %{}
    end
  end

  defp extract_meta_tags(html) do
    og_description =
      case Regex.run(~r/<meta\s+(?:property|name)="og:description"\s+content="([^"]*)"/, html) do
        [_, content] -> content
        _ -> nil
      end

    og_image =
      case Regex.run(~r/<meta\s+(?:property|name)="og:image"\s+content="([^"]*)"/, html) do
        [_, content] -> content
        _ -> nil
      end

    og_video =
      case Regex.run(~r/<meta\s+(?:property|name)="og:video"\s+content="([^"]*)"/, html) do
        [_, content] -> content
        _ -> nil
      end

    %{
      "description" => og_description,
      "image" => og_image,
      "video" => og_video
    }
  end

  defp extract_profile_display_name(html) do
    with [_, title] <- Regex.run(~r/<meta\s+(?:property|name)="og:title"\s+content="([^"]*)"/, html),
         [_, display_name] <- Regex.run(~r/^(.+?)\s+\(@/, decode_html_entities(title)) do
      display_name
    else
      _ -> nil
    end
  end

  defp extract_additional_data(html) do
    case Regex.run(~r/window\.__additionalData[^=]*=\s*(\{.*?\});/s, html) do
      [_, json_string] ->
        case Jason.decode(json_string) do
          {:ok, data} -> flatten_additional_data(data)
          {:error, _} -> %{}
        end

      _ ->
        %{}
    end
  end

  defp flatten_additional_data(data) when is_map(data) do
    shortcode_media = get_in(data, ["graphql", "shortcode_media"])

    first_item =
      case get_in(data, ["items"]) do
        [first | _] -> first
        _ -> nil
      end

    case shortcode_media || first_item do
      nil -> %{}
      result when is_map(result) -> result
    end
  end

  defp extract_media_urls(html, json_ld_data, additional_data) do
    urls_from_json_ld = extract_urls_from_json_ld(json_ld_data)
    urls_from_additional = extract_urls_from_additional(additional_data)
    urls_from_meta = extract_urls_from_meta(html)

    Enum.find(
      [urls_from_json_ld, urls_from_additional, urls_from_meta],
      [],
      fn urls -> urls != [] end
    )
  end

  defp extract_urls_from_json_ld(%{"image" => images}) when is_list(images) do
    images
    |> Enum.map(fn
      %{"url" => url} -> decode_html_entities(url)
      url when is_binary(url) -> decode_html_entities(url)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_urls_from_json_ld(%{"image" => url}) when is_binary(url), do: [decode_html_entities(url)]

  defp extract_urls_from_json_ld(%{"video" => %{"contentUrl" => url}}), do: [decode_html_entities(url)]
  defp extract_urls_from_json_ld(_), do: []

  defp extract_urls_from_additional(%{"display_url" => url}) when is_binary(url), do: [url]
  defp extract_urls_from_additional(%{"video_url" => url}) when is_binary(url), do: [url]

  defp extract_urls_from_additional(%{"edge_sidecar_to_children" => %{"edges" => edges}}) when is_list(edges) do
    edges
    |> Enum.map(fn
      %{"node" => %{"display_url" => url}} -> url
      %{"node" => %{"video_url" => url}} -> url
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_urls_from_additional(_), do: []

  defp extract_urls_from_post_item(item) do
    item
    |> post_item_media_urls()
    |> Enum.map(&decode_html_entities/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp post_item_media_urls(%{"edge_sidecar_to_children" => %{"edges" => edges}}) when is_list(edges) do
    Enum.flat_map(edges, fn
      %{"node" => node} -> post_item_media_urls(node)
      _ -> []
    end)
  end

  defp post_item_media_urls(%{"carousel_media" => carousel_media}) when is_list(carousel_media) do
    Enum.flat_map(carousel_media, &post_item_media_urls/1)
  end

  defp post_item_media_urls(%{"image_versions2" => %{"candidates" => candidates}}) when is_list(candidates) do
    candidates
    |> List.first()
    |> case do
      %{"url" => url} when is_binary(url) -> [url]
      _ -> []
    end
  end

  defp post_item_media_urls(%{"video_versions" => [%{"url" => url} | _]}) when is_binary(url), do: [url]
  defp post_item_media_urls(%{"display_url" => url}) when is_binary(url), do: [url]
  defp post_item_media_urls(%{"video_url" => url}) when is_binary(url), do: [url]
  defp post_item_media_urls(_item), do: []

  defp extract_urls_from_meta(html) do
    case Regex.run(~r/<meta\s+(?:property|name)="og:image"\s+content="([^"]*)"/, html) do
      [_, url] -> [decode_html_entities(url)]
      _ -> []
    end
  end

  defp extract_posted_at(json_ld_data, additional_data) do
    raw_timestamp =
      get_first_present([
        get_in(json_ld_data, ["datePublished"]),
        get_in(json_ld_data, ["uploadDate"]),
        additional_data["taken_at_timestamp"],
        additional_data["taken_at"]
      ])

    parse_timestamp(raw_timestamp)
  end

  defp extract_caption_date(caption) do
    case Regex.run(@caption_date_regex, caption) do
      [_, month_name, day, year] ->
        with month when is_integer(month) <- @month_numbers[month_name],
             {day_number, ""} <- Integer.parse(day),
             {year_number, ""} <- Integer.parse(year),
             {:ok, date} <- Date.new(year_number, month, day_number),
             {:ok, datetime} <- DateTime.new(date, ~T[12:00:00], "Etc/UTC") do
          datetime
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, datetime} -> DateTime.truncate(datetime, :second)
      {:error, _} -> nil
    end
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {unix, ""} ->
        parse_timestamp(unix)

      _ ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, datetime, _} -> DateTime.truncate(datetime, :second)
          {:error, _} -> nil
        end
    end
  end

  defp parse_timestamp(_), do: nil

  defp post_details_from_item(item) do
    caption = item |> extract_post_item_caption() |> decode_html_entities()
    media_urls = extract_urls_from_post_item(item)

    %{
      caption: caption || "",
      hashtags: extract_hashtags(caption || ""),
      posted_at: extract_post_item_timestamp(item) || extract_caption_date(caption || ""),
      post_type: determine_post_item_type(item, media_urls),
      media_urls: media_urls
    }
  end

  defp extract_post_item_caption(item) do
    get_first_present([
      get_in(item, ["edge_media_to_caption", "edges", Access.at(0), "node", "text"]),
      get_in(item, ["caption", "text"]),
      get_in(item, ["caption", "body"]),
      item["caption_text"],
      item["accessibility_caption"]
    ])
  end

  defp extract_post_item_timestamp(item) do
    [
      item["taken_at_timestamp"],
      item["taken_at"],
      item["created_time"]
    ]
    |> get_first_present()
    |> parse_timestamp()
  end

  defp determine_post_item_type(item, media_urls) do
    cond do
      item["product_type"] == "clips" -> "reel"
      item["__typename"] == "GraphVideo" -> "video"
      item["is_video"] == true -> "video"
      item["media_type"] == 2 -> "video"
      length(media_urls) > 1 -> "carousel"
      true -> "image"
    end
  end

  defp collect_post_items(items, shortcode) when is_list(items) do
    Enum.flat_map(items, &collect_post_items(&1, shortcode))
  end

  defp collect_post_items(%{} = item, shortcode) do
    nested_items =
      item
      |> Map.values()
      |> Enum.flat_map(&collect_post_items(&1, shortcode))

    if post_item?(item, shortcode), do: [item | nested_items], else: nested_items
  end

  defp collect_post_items(_item, _shortcode), do: []

  defp post_item?(item, shortcode) do
    shortcode in [
      item["shortcode"],
      item["code"],
      item["id"],
      item["pk"]
    ] and
      (extract_post_item_caption(item) not in [nil, ""] or extract_urls_from_post_item(item) != [])
  end

  defp classify_story_type(%{"video_url" => url}) when is_binary(url), do: "video"
  defp classify_story_type(%{"video_versions" => versions}) when is_list(versions), do: "video"
  defp classify_story_type(%{"media_type" => 2}), do: "video"
  defp classify_story_type(%{"is_video" => true}), do: "video"
  defp classify_story_type(_), do: "image"

  defp extract_story_media_url(%{"video_url" => url}) when is_binary(url), do: decode_html_entities(url)
  defp extract_story_media_url(%{"image_url" => url}) when is_binary(url), do: decode_html_entities(url)
  defp extract_story_media_url(%{"display_url" => url}) when is_binary(url), do: decode_html_entities(url)

  defp extract_story_media_url(%{"video_versions" => [%{"url" => url} | _]}) when is_binary(url) do
    decode_html_entities(url)
  end

  defp extract_story_media_url(%{"image_versions2" => %{"candidates" => candidates}}) when is_list(candidates) do
    candidates
    |> List.last()
    |> case do
      %{"url" => url} when is_binary(url) -> decode_html_entities(url)
      _ -> nil
    end
  end

  defp extract_story_media_url(_), do: nil

  defp collect_story_items(items) when is_list(items), do: Enum.flat_map(items, &collect_story_items/1)

  defp collect_story_items(%{} = item) do
    nested_items =
      item
      |> Map.values()
      |> Enum.flat_map(&collect_story_items/1)

    if story_item?(item), do: [item | nested_items], else: nested_items
  end

  defp collect_story_items(_), do: []

  defp story_item?(%{} = item) do
    (is_binary(item["id"]) or is_integer(item["pk"]) or is_binary(item["pk"])) and
      is_binary(extract_story_media_url(item))
  end

  defp has_video_indicator?(html) do
    String.contains?(html, "og:video") or String.contains?(html, "\"is_video\":true")
  end

  defp generate_story_id do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @html_entities [
    {"&amp;", "&"},
    {"&quot;", "\""},
    {"&#39;", "'"},
    {"&apos;", "'"},
    {"&lt;", "<"},
    {"&gt;", ">"},
    {"&nbsp;", " "}
  ]

  defp decode_html_entities(nil), do: nil

  defp decode_html_entities(text) when is_binary(text) do
    Enum.reduce(@html_entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  defp get_first_present(values) do
    Enum.find(values, fn
      nil -> false
      "" -> false
      _ -> true
    end)
  end
end
