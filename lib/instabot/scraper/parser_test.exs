defmodule Instabot.Scraper.ParserTest do
  use ExUnit.Case, async: true

  alias Instabot.Scraper.Parser

  @profile_html_with_posts """
  <html>
  <body>
    <div class="profile">
      <a href="/p/ABC123def/">Post 1</a>
      <a href="/p/XYZ789ghi/">Post 2</a>
      <a href="/reel/REEL001jk/">Reel 1</a>
    </div>
  </body>
  </html>
  """

  @profile_html_empty """
  <html><body><div class="profile">No posts yet</div></body></html>
  """

  @post_html_with_json_ld """
  <html>
  <head>
    <script type="application/ld+json">
    {
      "articleBody": "Beautiful sunset today! #nature #photography #sunset",
      "datePublished": "2026-03-15T10:30:00Z",
      "image": ["https://instagram.com/p/img1.jpg", "https://instagram.com/p/img2.jpg"]
    }
    </script>
    <meta property="og:description" content="Beautiful sunset today!">
    <meta property="og:image" content="https://instagram.com/p/img1.jpg">
  </head>
  <body></body>
  </html>
  """

  @post_html_with_video """
  <html>
  <head>
    <script type="application/ld+json">
    {
      "articleBody": "Check this out",
      "video": {"contentUrl": "https://instagram.com/p/video1.mp4"}
    }
    </script>
    <meta property="og:video" content="https://instagram.com/p/video1.mp4">
  </head>
  <body></body>
  </html>
  """

  @post_html_meta_only """
  <html>
  <head>
    <meta property="og:description" content="A simple post #hello">
    <meta property="og:image" content="https://instagram.com/p/meta_img.jpg">
  </head>
  <body></body>
  </html>
  """

  @login_page_html """
  <html>
  <head><title>Login • Instagram</title></head>
  <body>
    <form id="loginForm" action="/accounts/login/">
      <input name="username">
      <input name="password">
      <button>Log in to Instagram</button>
    </form>
  </body>
  </html>
  """

  @normal_page_html """
  <html>
  <head><title>Instagram</title></head>
  <body><div class="feed">Welcome to Instagram</div></body>
  </html>
  """

  @two_factor_html """
  <html>
  <head><title>Instagram</title></head>
  <body>
    <h1>Two-Factor Authentication Required</h1>
    <p>Enter the security code we sent to your phone.</p>
    <form id="twoFactorForm">
      <input name="verificationCode" />
      <button>Confirm</button>
    </form>
  </body>
  </html>
  """

  @error_incorrect_password_html """
  <html><body>
    <form id="loginForm" action="/accounts/login/">
      <div role="alert">Sorry, your password was incorrect. Please double-check your password.</div>
    </form>
  </body></html>
  """

  @error_rate_limited_html """
  <html><body>
    <div>Please wait a few minutes before you try again.</div>
  </body></html>
  """

  @error_suspicious_html """
  <html><body>
    <div>We detected a suspicious login attempt on your account.</div>
  </body></html>
  """

  @error_username_not_found_html """
  <html><body>
    <div>The username you entered doesn't belong to an account.</div>
  </body></html>
  """

  @error_challenge_html """
  <html><body><script>window.location = "/challenge_required/";</script></body></html>
  """

  @error_checkpoint_html """
  <html><body><script>window.location = "/checkpoint_required/";</script></body></html>
  """

  describe "extract_posts_from_profile/1" do
    test "extracts post shortcodes and permalinks from profile HTML" do
      posts = Parser.extract_posts_from_profile(@profile_html_with_posts)

      assert length(posts) == 3

      shortcodes = Enum.map(posts, & &1.instagram_post_id)
      assert "ABC123def" in shortcodes
      assert "XYZ789ghi" in shortcodes
      assert "REEL001jk" in shortcodes
    end

    test "returns empty list for profile with no posts" do
      assert [] == Parser.extract_posts_from_profile(@profile_html_empty)
    end

    test "deduplicates shortcodes when same post appears multiple times" do
      html_with_dupes = """
      <html><body>
        <a href="/p/ABC123/">Post</a>
        <a href="/p/ABC123/">Same Post</a>
      </body></html>
      """

      posts = Parser.extract_posts_from_profile(html_with_dupes)
      assert length(posts) == 1
    end

    test "generates correct permalink format" do
      [post | _] = Parser.extract_posts_from_profile(@profile_html_with_posts)
      assert String.starts_with?(post.permalink, "https://www.instagram.com/")
    end
  end

  describe "extract_post_details/1" do
    test "extracts caption and hashtags from JSON-LD" do
      details = Parser.extract_post_details(@post_html_with_json_ld)

      assert "Beautiful sunset today! #nature #photography #sunset" == details.caption
      assert "nature" in details.hashtags
      assert "photography" in details.hashtags
      assert "sunset" in details.hashtags
    end

    test "extracts posted_at datetime from JSON-LD" do
      details = Parser.extract_post_details(@post_html_with_json_ld)
      assert %DateTime{} = details.posted_at
      assert ~U[2026-03-15 10:30:00Z] == details.posted_at
    end

    test "extracts media URLs from JSON-LD image array" do
      details = Parser.extract_post_details(@post_html_with_json_ld)
      assert length(details.media_urls) == 2
      assert "https://instagram.com/p/img1.jpg" in details.media_urls
    end

    test "classifies carousel when multiple images present" do
      details = Parser.extract_post_details(@post_html_with_json_ld)
      assert "carousel" == details.post_type
    end

    test "falls back to meta tags when no JSON-LD present" do
      details = Parser.extract_post_details(@post_html_meta_only)
      assert "A simple post #hello" == details.caption
      assert ["hello"] == details.hashtags
      assert ["https://instagram.com/p/meta_img.jpg"] == details.media_urls
    end

    test "detects video post type" do
      details = Parser.extract_post_details(@post_html_with_video)
      assert "video" == details.post_type
    end

    test "uses caption metadata date when structured date is missing" do
      html = """
      <html>
      <head>
        <meta property="og:description" content="1,762 likes, 70 comments - caledarrellusa on October 5, 2023: &quot;Sometimes...&quot;">
        <meta property="og:image" content="https://cdn.instagram.com/image.jpg">
      </head>
      <body></body>
      </html>
      """

      assert %{posted_at: posted_at} = Parser.extract_post_details(html)
      assert ~D[2023-10-05] == DateTime.to_date(posted_at)
    end
  end

  describe "extract_post_details_from_responses/2" do
    test "extracts post details from GraphQL shortcode media responses" do
      responses = [
        %{
          "url" => "https://www.instagram.com/graphql/query",
          "body" => %{
            "data" => %{
              "xdt_shortcode_media" => %{
                "shortcode" => "ABC123def",
                "edge_media_to_caption" => %{
                  "edges" => [
                    %{"node" => %{"text" => "JSON caption #Vintage"}}
                  ]
                },
                "taken_at_timestamp" => 1_774_112_400,
                "display_url" => "https://cdn.instagram.com/post.jpg",
                "__typename" => "GraphImage"
              }
            }
          }
        }
      ]

      details = Parser.extract_post_details_from_responses(responses, "ABC123def")

      assert %{
               caption: "JSON caption #Vintage",
               hashtags: ["vintage"],
               media_urls: ["https://cdn.instagram.com/post.jpg"],
               post_type: "image",
               posted_at: ~U[2026-03-21 17:00:00Z]
             } == details
    end

    test "extracts carousel media URLs from nested response items" do
      responses = [
        %{
          "body" => %{
            "items" => [
              %{
                "code" => "CAROUSEL1",
                "caption" => %{"text" => "Carousel post"},
                "carousel_media" => [
                  %{"image_versions2" => %{"candidates" => [%{"url" => "https://cdn.instagram.com/one.jpg"}]}},
                  %{"video_versions" => [%{"url" => "https://cdn.instagram.com/two.mp4"}]}
                ]
              }
            ]
          }
        }
      ]

      details = Parser.extract_post_details_from_responses(responses, "CAROUSEL1")

      assert "Carousel post" == details.caption
      assert "carousel" == details.post_type

      assert [
               "https://cdn.instagram.com/one.jpg",
               "https://cdn.instagram.com/two.mp4"
             ] == details.media_urls
    end

    test "returns nil when responses do not include the shortcode" do
      responses = [
        %{"body" => %{"items" => [%{"code" => "OTHER", "display_url" => "https://cdn.instagram.com/post.jpg"}]}}
      ]

      assert nil == Parser.extract_post_details_from_responses(responses, "MISSING")
    end
  end

  describe "extract_profile_metadata/1" do
    test "extracts display name and profile image from profile page meta tags" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="Cale Darrell (@caledarrellusa) • Instagram photos and videos">
        <meta property="og:image" content="https://cdn.instagram.com/avatar.jpg?foo=1&amp;bar=2">
      </head>
      <body></body>
      </html>
      """

      assert %{
               display_name: "Cale Darrell",
               profile_pic_url: "https://cdn.instagram.com/avatar.jpg?foo=1&bar=2"
             } == Parser.extract_profile_metadata(html)
    end
  end

  describe "extract_hashtags/1" do
    test "extracts hashtags from a caption" do
      hashtags = Parser.extract_hashtags("Hello #world #elixir")
      assert ["world", "elixir"] == hashtags
    end

    test "returns empty list when no hashtags" do
      assert [] == Parser.extract_hashtags("No hashtags here")
    end

    test "lowercases hashtags" do
      assert ["elixir"] == Parser.extract_hashtags("#ELIXIR")
    end

    test "deduplicates hashtags" do
      assert ["hello"] == Parser.extract_hashtags("#hello #hello")
    end

    test "handles nil input" do
      assert [] == Parser.extract_hashtags(nil)
    end

    test "handles empty string" do
      assert [] == Parser.extract_hashtags("")
    end
  end

  describe "extract_stories/1" do
    test "extracts story metadata from JS data" do
      js_data = [
        %{
          "id" => "story_001",
          "is_video" => false,
          "image_url" => "https://instagram.com/stories/img1.jpg",
          "taken_at_timestamp" => 1_710_000_000,
          "expiring_at_timestamp" => 1_710_086_400
        }
      ]

      [story] = Parser.extract_stories(js_data)
      assert "story_001" == story.instagram_story_id
      assert "image" == story.story_type
      assert "https://instagram.com/stories/img1.jpg" == story.media_url
      assert %DateTime{} = story.posted_at
      assert %DateTime{} = story.expires_at
    end

    test "classifies video stories" do
      js_data = [
        %{
          "id" => "story_002",
          "video_url" => "https://instagram.com/stories/video1.mp4",
          "taken_at" => 1_710_000_000
        }
      ]

      [story] = Parser.extract_stories(js_data)
      assert "video" == story.story_type
      assert "https://instagram.com/stories/video1.mp4" == story.media_url
    end

    test "generates story ID when none provided" do
      js_data = [%{"image_url" => "https://example.com/img.jpg"}]
      [story] = Parser.extract_stories(js_data)
      assert is_binary(story.instagram_story_id)
      assert String.length(story.instagram_story_id) > 0
    end

    test "returns empty list for nil input" do
      assert [] == Parser.extract_stories(nil)
    end

    test "returns empty list for empty list" do
      assert [] == Parser.extract_stories([])
    end
  end

  describe "extract_stories_from_responses/1" do
    test "extracts stories from reels_media network payloads" do
      responses = [
        %{
          "url" => "https://www.instagram.com/api/v1/feed/reels_media/",
          "body" => %{
            "reels_media" => [
              %{
                "items" => [
                  %{
                    "pk" => "story_123",
                    "media_type" => 1,
                    "image_versions2" => %{
                      "candidates" => [
                        %{"url" => "https://cdn.instagram.com/small.jpg"},
                        %{"url" => "https://cdn.instagram.com/large.jpg?x=1&amp;y=2"}
                      ]
                    },
                    "taken_at" => 1_710_000_000,
                    "expiring_at" => 1_710_086_400
                  }
                ]
              }
            ]
          }
        }
      ]

      assert [story] = Parser.extract_stories_from_responses(responses)
      assert "story_123" == story.instagram_story_id
      assert "image" == story.story_type
      assert "https://cdn.instagram.com/large.jpg?x=1&y=2" == story.media_url
      assert %DateTime{} = story.posted_at
      assert %DateTime{} = story.expires_at
    end

    test "extracts video story URLs from nested GraphQL payloads" do
      responses = [
        %{
          "body" => %{
            "data" => %{
              "xdt_api__v1__feed__reels_media__connection" => %{
                "edges" => [
                  %{
                    "node" => %{
                      "items" => [
                        %{
                          "id" => "story_video",
                          "video_versions" => [%{"url" => "https://cdn.instagram.com/video.mp4"}],
                          "image_versions2" => %{
                            "candidates" => [
                              %{"url" => "https://cdn.instagram.com/small.jpg"},
                              %{"url" => "https://cdn.instagram.com/large.jpg"}
                            ]
                          },
                          "taken_at_timestamp" => 1_710_000_000
                        }
                      ]
                    }
                  }
                ]
              }
            }
          }
        }
      ]

      assert [story] = Parser.extract_stories_from_responses(responses)
      assert "story_video" == story.instagram_story_id
      assert "video" == story.story_type
      assert "https://cdn.instagram.com/video.mp4" == story.media_url
      assert "https://cdn.instagram.com/large.jpg" == story.thumbnail_url
    end
  end

  describe "login_page?/1" do
    test "returns true for login page HTML" do
      assert Parser.login_page?(@login_page_html)
    end

    test "returns false for normal page HTML" do
      refute Parser.login_page?(@normal_page_html)
    end

    test "returns false for nil" do
      refute Parser.login_page?(nil)
    end

    test "detects login redirect URL" do
      redirect_html = ~s(<html><body>Redirecting to /accounts/login/?next=/p/ABC/</body></html>)
      assert Parser.login_page?(redirect_html)
    end
  end

  describe "two_factor_page?/1" do
    test "returns true for 2FA page with security code and verification form" do
      assert Parser.two_factor_page?(@two_factor_html)
    end

    test "detects case-insensitive indicators" do
      html = "<html><body><p>Enter The Code we sent to your device</p></body></html>"
      assert Parser.two_factor_page?(html)
    end

    test "detects confirmationCode input" do
      html = ~s(<html><body><input name="confirmationCode" /></body></html>)
      assert Parser.two_factor_page?(html)
    end

    test "detects Confirm Your Identity page" do
      html = "<html><body><h2>Confirm Your Identity</h2></body></html>"
      assert Parser.two_factor_page?(html)
    end

    test "returns false for normal page" do
      refute Parser.two_factor_page?(@normal_page_html)
    end

    test "returns false for login page" do
      refute Parser.two_factor_page?(@login_page_html)
    end

    test "returns false for nil" do
      refute Parser.two_factor_page?(nil)
    end
  end

  describe "login_error?/1" do
    test "returns {:error, :incorrect_password} for wrong password" do
      assert {:error, :incorrect_password} == Parser.login_error?(@error_incorrect_password_html)
    end

    test "returns {:error, :rate_limited} for rate limit page" do
      assert {:error, :rate_limited} == Parser.login_error?(@error_rate_limited_html)
    end

    test "returns {:error, :suspicious_attempt} for suspicious login" do
      assert {:error, :suspicious_attempt} == Parser.login_error?(@error_suspicious_html)
    end

    test "returns {:error, :username_not_found} for invalid username" do
      assert {:error, :username_not_found} == Parser.login_error?(@error_username_not_found_html)
    end

    test "returns {:error, :challenge_required} for challenge page" do
      assert {:error, :challenge_required} == Parser.login_error?(@error_challenge_html)
    end

    test "returns {:error, :checkpoint_required} for checkpoint page" do
      assert {:error, :checkpoint_required} == Parser.login_error?(@error_checkpoint_html)
    end

    test "returns :ok for normal page with no errors" do
      assert :ok == Parser.login_error?(@normal_page_html)
    end

    test "returns :ok for nil" do
      assert :ok == Parser.login_error?(nil)
    end
  end

  describe "determine_post_type/2" do
    test "detects reel from HTML" do
      assert "reel" == Parser.determine_post_type([], ~s(<a href="/reel/ABC123/">))
    end

    test "detects carousel from multiple URLs" do
      urls = ["https://img1.jpg", "https://img2.jpg"]
      assert "carousel" == Parser.determine_post_type(urls, "<html></html>")
    end

    test "detects video from og:video meta tag" do
      html = ~s(<meta property="og:video" content="https://video.mp4">)
      assert "video" == Parser.determine_post_type([], html)
    end

    test "defaults to image" do
      assert "image" == Parser.determine_post_type([], "<html></html>")
    end
  end
end
