alias Instabot.Accounts
alias Instabot.Accounts.User
alias Instabot.Encryption
alias Instabot.Instagram
alias Instabot.Repo

import Ecto.Query

e2e_email = "e2e@test.com"
e2e_password = "hello world!"

user =
  case Repo.get_by(User, email: e2e_email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: e2e_email})

      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [confirmed_at: DateTime.utc_now(:second)]
      )

      user = Repo.get!(User, user.id)
      {:ok, {user, _}} = Accounts.update_user_password(user, %{password: e2e_password})
      IO.puts("Created and confirmed user: #{e2e_email}")
      user

    existing ->
      IO.puts("User already exists: #{e2e_email}")
      existing
  end

connection =
  case Instagram.get_connection_for_user(user.id) do
    nil ->
      {:ok, connection} =
        Instagram.create_connection(user.id, %{
          instagram_username: "e2e_tester",
          status: "connecting"
        })

      encrypted_cookies =
        Encryption.encrypt_term([
          %{
            "name" => "sessionid",
            "value" => "fake_session_e2e",
            "domain" => ".instagram.com",
            "path" => "/",
            "httpOnly" => true,
            "secure" => true
          },
          %{
            "name" => "csrftoken",
            "value" => "fake_csrf_e2e",
            "domain" => ".instagram.com",
            "path" => "/",
            "httpOnly" => false,
            "secure" => true
          }
        ])

      {:ok, connection} =
        Instagram.store_cookies(connection, encrypted_cookies, DateTime.add(DateTime.utc_now(), 90, :day))

      IO.puts("Created Instagram connection: @e2e_tester")
      connection

    existing ->
      IO.puts("Instagram connection already exists")
      existing
  end

profiles_config = [
  %{instagram_username: "natgeo", display_name: "National Geographic", is_active: true},
  %{instagram_username: "nasa", display_name: "NASA", is_active: true},
  %{instagram_username: "spacex", display_name: "SpaceX", is_active: false}
]

existing_profiles = Instagram.list_tracked_profiles(user.id)
existing_usernames = Enum.map(existing_profiles, & &1.instagram_username)

profiles =
  Enum.map(profiles_config, fn config ->
    if config.instagram_username in existing_usernames do
      profile = Enum.find(existing_profiles, &(&1.instagram_username == config.instagram_username))
      IO.puts("Profile already exists: @#{config.instagram_username}")
      profile
    else
      {:ok, profile} = Instagram.create_tracked_profile(user.id, config)
      IO.puts("Created profile: @#{config.instagram_username}")
      profile
    end
  end)

[natgeo, nasa, spacex] = profiles

now = DateTime.utc_now(:second)

post_templates = [
  %{profile: natgeo, caption: "The aurora borealis lights up the Arctic sky in a breathtaking display of nature", hashtags: ["nature", "aurora", "arctic", "photography"], type: "image"},
  %{profile: natgeo, caption: "A lone polar bear traverses the frozen tundra", hashtags: ["nature", "wildlife", "arctic"], type: "image"},
  %{profile: natgeo, caption: "Sunrise over the Sahara Desert reveals hidden dune patterns", hashtags: ["nature", "desert", "photography"], type: "carousel"},
  %{profile: natgeo, caption: "Deep ocean creatures glow with bioluminescence in the midnight zone", hashtags: ["ocean", "nature", "science"], type: "image"},
  %{profile: natgeo, caption: "Ancient redwood forests tower above the morning fog", hashtags: ["nature", "forest", "california"], type: "carousel"},
  %{profile: natgeo, caption: "Volcanic eruption captured at twilight from a safe distance", hashtags: ["nature", "volcano", "geology"], type: "image"},
  %{profile: natgeo, caption: "Migration season brings millions of monarch butterflies through Mexico", hashtags: ["nature", "wildlife", "migration"], type: "image"},
  %{profile: natgeo, caption: "Crystal clear waters reveal the coral reef ecosystem below", hashtags: ["ocean", "nature", "diving"], type: "carousel"},
  %{profile: natgeo, caption: "Lightning strikes illuminate the Grand Canyon at midnight", hashtags: ["nature", "storm", "landscape"], type: "image"},
  %{profile: natgeo, caption: "The Milky Way arches over Patagonia's iconic peaks", hashtags: ["nature", "astronomy", "landscape"], type: "image"},
  %{profile: nasa, caption: "Rocket launch from Kennedy Space Center sends crew to the ISS", hashtags: ["space", "nasa", "rocket", "launch"], type: "image"},
  %{profile: nasa, caption: "Hubble captures a stunning nebula 6500 light years away", hashtags: ["space", "astronomy", "hubble"], type: "image"},
  %{profile: nasa, caption: "Mars rover Perseverance discovers mineral deposits in Jezero Crater", hashtags: ["space", "mars", "rover", "science"], type: "carousel"},
  %{profile: nasa, caption: "Earth from orbit shows hurricane season in full force", hashtags: ["space", "earth", "weather"], type: "image"},
  %{profile: nasa, caption: "James Webb telescope reveals the earliest galaxies ever observed", hashtags: ["space", "astronomy", "jwst"], type: "image"},
  %{profile: nasa, caption: "Astronaut captures a stunning orbital sunset from the ISS cupola", hashtags: ["space", "iss", "photography"], type: "image"},
  %{profile: nasa, caption: "Saturn's rings in unprecedented detail from Cassini archive data", hashtags: ["space", "saturn", "astronomy"], type: "carousel"},
  %{profile: nasa, caption: "SpaceX Dragon capsule docks with the International Space Station", hashtags: ["space", "iss", "dragon"], type: "image"},
  %{profile: nasa, caption: "Solar flare eruption captured by the Solar Dynamics Observatory", hashtags: ["space", "sun", "science"], type: "image"},
  %{profile: nasa, caption: "Artemis mission prepares for the next lunar landing attempt", hashtags: ["space", "moon", "artemis"], type: "image"},
  %{profile: spacex, caption: "Starship prototype completes a full orbital test flight", hashtags: ["space", "starship", "spacex"], type: "image"},
  %{profile: spacex, caption: "Falcon 9 booster lands on the drone ship for the 20th time", hashtags: ["space", "falcon9", "landing"], type: "carousel"},
  %{profile: spacex, caption: "Starlink satellites deploy from the fairing in a mesmerizing sequence", hashtags: ["space", "starlink", "internet"], type: "image"},
  %{profile: spacex, caption: "Raptor engine test fire at McGregor facility", hashtags: ["space", "raptor", "engineering"], type: "image"},
  %{profile: spacex, caption: "Crew Dragon interior showcasing the next-generation flight deck", hashtags: ["space", "dragon", "crew"], type: "carousel"},
  %{profile: spacex, caption: "Boca Chica launch site at sunset with Starship on the pad", hashtags: ["space", "starship", "texas"], type: "image"},
  %{profile: spacex, caption: "Side boosters land simultaneously after Falcon Heavy launch", hashtags: ["space", "falconheavy", "landing"], type: "image"},
  %{profile: spacex, caption: "Starship heat shield tiles undergo thermal testing", hashtags: ["space", "starship", "engineering"], type: "image"},
  %{profile: spacex, caption: "Full stack Starship stands 120 meters tall on the orbital launch mount", hashtags: ["space", "starship", "launch"], type: "carousel"},
  %{profile: spacex, caption: "Night launch of Falcon 9 lights up the Florida coast", hashtags: ["space", "falcon9", "launch", "photography"], type: "image"},
  %{profile: natgeo, caption: "Underwater photography reveals the hidden world beneath Antarctic ice", hashtags: ["nature", "ocean", "arctic", "photography"], type: "image"},
  %{profile: nasa, caption: "Black hole visualization based on new Event Horizon Telescope data", hashtags: ["space", "astronomy", "blackhole", "science"], type: "image"}
]

existing_post_count = Instagram.count_posts(user.id)

if existing_post_count >= 30 do
  IO.puts("Posts already seeded (#{existing_post_count} exist)")
else
  Enum.with_index(post_templates, fn template, index ->
    days_ago = 30 - index
    posted_at = DateTime.add(now, -days_ago * 24 * 3600, :second)

    media_url_count =
      case template.type do
        "carousel" -> Enum.random(3..5)
        _ -> 1
      end

    media_urls = Enum.map(1..media_url_count, fn n -> "https://example.com/#{template.profile.instagram_username}/post_#{index}_#{n}.jpg" end)

    {:ok, post} =
      Instagram.create_post(template.profile.id, %{
        instagram_post_id: "#{template.profile.instagram_username}_post_#{index}",
        post_type: template.type,
        caption: template.caption,
        hashtags: template.hashtags,
        media_urls: media_urls,
        permalink: "https://instagram.com/p/#{template.profile.instagram_username}_#{index}",
        posted_at: posted_at
      })

    if template.type == "carousel" do
      Enum.each(Enum.with_index(media_urls), fn {url, position} ->
        Instagram.create_post_image(post.id, %{
          original_url: url,
          local_path: "/images/placeholder.png",
          position: position,
          content_type: "image/jpeg"
        })
      end)
    else
      Instagram.create_post_image(post.id, %{
        original_url: List.first(media_urls),
        local_path: "/images/placeholder.png",
        position: 0,
        content_type: "image/jpeg"
      })
    end
  end)

  IO.puts("Created #{length(post_templates)} posts with images")
end

story_days = [-1, -2, -3, -5, -7, -10]

story_templates = [
  %{profile: natgeo, ocr_text: "BREAKING: New species discovered in the Amazon rainforest. Scientists estimate over 300 undiscovered species remain.", has_ocr: true},
  %{profile: natgeo, ocr_text: nil, has_ocr: false},
  %{profile: natgeo, ocr_text: "National Geographic Explorer of the Year award ceremony tonight at 8PM EST", has_ocr: true},
  %{profile: natgeo, ocr_text: nil, has_ocr: false},
  %{profile: natgeo, ocr_text: "Climate report shows Arctic ice at record lows for the third consecutive year", has_ocr: true},
  %{profile: nasa, ocr_text: "LIVE NOW: Artemis III crew selection announcement. Watch on nasa.gov", has_ocr: true},
  %{profile: nasa, ocr_text: nil, has_ocr: false},
  %{profile: nasa, ocr_text: "Mars weather update: dust storm season begins. Rover operations adjusted.", has_ocr: true},
  %{profile: nasa, ocr_text: nil, has_ocr: false},
  %{profile: nasa, ocr_text: "ISS crew completes 6-hour spacewalk to replace solar array batteries", has_ocr: true},
  %{profile: nasa, ocr_text: "JWST discovers water vapor in exoplanet atmosphere 120 light years away", has_ocr: true},
  %{profile: nasa, ocr_text: nil, has_ocr: false},
  %{profile: spacex, ocr_text: "Next Starship launch window: April 20, 2026. Follow along at spacex.com/launches", has_ocr: true},
  %{profile: spacex, ocr_text: nil, has_ocr: false},
  %{profile: spacex, ocr_text: "Starlink now available in 80 countries. Over 6000 satellites in orbit.", has_ocr: true},
  %{profile: spacex, ocr_text: nil, has_ocr: false},
  %{profile: spacex, ocr_text: "Behind the scenes: Raptor 3 engine assembly in Hawthorne, CA", has_ocr: true},
  %{profile: natgeo, ocr_text: "Photo of the Day contest is now open. Submit your best wildlife shots.", has_ocr: true},
  %{profile: natgeo, ocr_text: nil, has_ocr: false},
  %{profile: nasa, ocr_text: "Voyager 1 continues transmitting data from interstellar space after 48 years", has_ocr: true},
  %{profile: nasa, ocr_text: nil, has_ocr: false},
  %{profile: spacex, ocr_text: "Crew-9 mission patch revealed. Launch scheduled for next month.", has_ocr: true},
  %{profile: spacex, ocr_text: nil, has_ocr: false},
  %{profile: natgeo, ocr_text: "The last remaining high-altitude glaciers are melting at an alarming rate", has_ocr: true},
  %{profile: nasa, ocr_text: nil, has_ocr: false},
  %{profile: spacex, ocr_text: nil, has_ocr: false},
  %{profile: natgeo, ocr_text: "Expedition to the Mariana Trench discovers new thermal vent communities", has_ocr: true},
  %{profile: nasa, ocr_text: "Total solar eclipse path crosses North America in 2026. Are you ready?", has_ocr: true},
  %{profile: spacex, ocr_text: "Mechazilla catch tower upgrade nearing completion at Starbase", has_ocr: true},
  %{profile: natgeo, ocr_text: nil, has_ocr: false},
  %{profile: nasa, ocr_text: nil, has_ocr: false},
  %{profile: spacex, ocr_text: "SpaceX surpasses 300 successful Falcon 9 missions", has_ocr: true}
]

existing_story_count = Instagram.count_stories(user.id)

if existing_story_count >= 30 do
  IO.puts("Stories already seeded (#{existing_story_count} exist)")
else
  Enum.with_index(story_templates, fn template, index ->
    day_offset = Enum.at(story_days, rem(index, length(story_days)))
    hour_offset = rem(index * 3, 24)
    posted_at = DateTime.add(now, day_offset * 24 * 3600 + hour_offset * 3600, :second)
    expires_at = DateTime.add(posted_at, 24 * 3600, :second)

    story_attrs = %{
      instagram_story_id: "#{template.profile.instagram_username}_story_#{index}",
      story_type: "image",
      screenshot_path: "/images/placeholder.png",
      posted_at: posted_at,
      expires_at: expires_at
    }

    story_attrs =
      if template.has_ocr do
        Map.merge(story_attrs, %{ocr_status: "completed", ocr_text: template.ocr_text})
      else
        Map.put(story_attrs, :ocr_status, "pending")
      end

    Instagram.create_story(template.profile.id, story_attrs)
  end)

  IO.puts("Created #{length(story_templates)} stories")
end

IO.puts("\nE2E seed complete!")
IO.puts("  User: #{e2e_email} / #{e2e_password}")
IO.puts("  Connection: @e2e_tester (connected)")
IO.puts("  Profiles: @natgeo (active), @nasa (active), @spacex (paused)")
IO.puts("  Posts: #{length(post_templates)}")
IO.puts("  Stories: #{length(story_templates)}")
