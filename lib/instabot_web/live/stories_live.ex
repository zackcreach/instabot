defmodule InstabotWeb.StoriesLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Instagram.Events
  alias Instabot.Instagram.Feed
  alias Instabot.Media
  alias InstabotWeb.DateTimeFormatter

  @page_size Feed.default_limit()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Stories</h1>
          <.link navigate={~p"/feed"} class="btn btn-ghost btn-sm">
            <.icon name="hero-photo" class="size-4" /> Posts
          </.link>
        </div>

        <form id="profile-filter" phx-change="filter_profile" class="sm:w-64">
          <select name="profile_id" class="select select-bordered w-full">
            <option value="">All profiles</option>
            <option
              :for={profile <- @profiles}
              value={profile.id}
              selected={@profile_id == profile.id}
            >
              @{profile.instagram_username}
            </option>
          </select>
        </form>

        <div :if={@stories == []} class="text-center py-16 opacity-70">
          <.icon name="hero-film" class="size-12 opacity-30 mx-auto mb-4" />
          <h3 class="text-lg font-semibold mb-2">No stories yet</h3>
          <p class="text-sm">
            Stories appear here after scraping. They expire after 24 hours on Instagram but stay here indefinitely.
          </p>
        </div>

        <div :if={@stories != []} class="space-y-6">
          <section :for={{day, day_stories} <- @grouped_stories} class="space-y-3">
            <h3 class="text-sm font-semibold opacity-70">{day}</h3>
            <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              <.link
                :for={story <- day_stories}
                id={"story-#{story.id}"}
                patch={~p"/feed/stories/#{story.id}"}
                class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer"
              >
                <figure class="aspect-[9/16] bg-base-300 overflow-hidden">
                  <img
                    :if={story_preview_url(story)}
                    src={story_preview_url(story)}
                    alt="Story screenshot"
                    class="w-full h-full object-cover"
                  />
                  <div
                    :if={!story_preview_url(story)}
                    class="flex items-center justify-center w-full h-full"
                  >
                    <.icon name="hero-film" class="size-10 opacity-30" />
                  </div>
                </figure>
                <div class="card-body p-3">
                  <div class="flex items-center gap-2">
                    <div class={[
                      "avatar",
                      is_nil(profile_avatar_url(story.tracked_profile)) && "placeholder"
                    ]}>
                      <div class="bg-neutral text-neutral-content w-6 rounded-full">
                        <img
                          :if={profile_avatar_url(story.tracked_profile)}
                          src={profile_avatar_url(story.tracked_profile)}
                          alt={story.tracked_profile.instagram_username}
                        />
                        <span :if={is_nil(profile_avatar_url(story.tracked_profile))} class="text-xs">
                          {String.first(story.tracked_profile.instagram_username) |> String.upcase()}
                        </span>
                      </div>
                    </div>
                    <span class="text-xs font-medium truncate">
                      @{story.tracked_profile.instagram_username}
                    </span>
                    <span class="text-xs opacity-50 ml-auto shrink-0 text-right">
                      {DateTimeFormatter.relative(story.posted_at)}
                    </span>
                  </div>
                  <p :if={story.ocr_text} class="text-xs line-clamp-3 opacity-70 mt-1">
                    {story.ocr_text}
                  </p>
                </div>
              </.link>
            </div>
          </section>
        </div>

        <div
          :if={@stories != [] and length(@stories) < @total_stories}
          id="stories-sentinel"
          phx-hook=".InfiniteScroll"
          class="flex justify-center py-4"
        >
          <span class="loading loading-dots loading-md opacity-50"></span>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".InfiniteScroll">
        export default {
          mounted() {
            this.observer = new IntersectionObserver(
              ([entry]) => {
                if (entry.isIntersecting) {
                  this.observer.disconnect();
                  this.pushEvent("load_more");
                }
              },
              { rootMargin: "200px" }
            );
            this.observer.observe(this.el);
          },
          updated() {
            this.observer.observe(this.el);
          },
          destroyed() {
            this.observer.disconnect();
          }
        };
      </script>

      <div :if={@selected_story} id="story-modal" class="modal modal-open" role="dialog">
        <div class="modal-box max-w-lg">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2">
              <div class={[
                "avatar",
                is_nil(profile_avatar_url(@selected_story.tracked_profile)) && "placeholder"
              ]}>
                <div class="bg-neutral text-neutral-content w-8 rounded-full">
                  <img
                    :if={profile_avatar_url(@selected_story.tracked_profile)}
                    src={profile_avatar_url(@selected_story.tracked_profile)}
                    alt={@selected_story.tracked_profile.instagram_username}
                  />
                  <span
                    :if={is_nil(profile_avatar_url(@selected_story.tracked_profile))}
                    class="text-xs"
                  >
                    {String.first(@selected_story.tracked_profile.instagram_username)
                    |> String.upcase()}
                  </span>
                </div>
              </div>
              <div>
                <div class="font-semibold">@{@selected_story.tracked_profile.instagram_username}</div>
                <div class="text-xs opacity-50">
                  {DateTimeFormatter.relative(@selected_story.posted_at)}
                </div>
              </div>
            </div>
            <.link
              patch={~p"/feed/stories"}
              class="btn btn-ghost btn-sm btn-circle"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </.link>
          </div>

          <div
            id={"lightbox-#{@selected_story.id}"}
            class="aspect-[9/16] bg-base-300 rounded overflow-hidden mb-4 max-h-[60vh] max-w-[360px] mx-auto"
          >
            <a
              :if={story_preview_url(@selected_story)}
              id="story-modal-image-link"
              href={story_preview_url(@selected_story)}
              target="_blank"
              rel="noopener noreferrer"
              class="block w-full h-full"
              aria-label="Open image"
            >
              <img
                src={story_preview_url(@selected_story)}
                alt="Story screenshot"
                class="w-full h-full object-cover"
              />
            </a>
          </div>

          <div :if={@selected_story.ocr_text} class="mb-3">
            <h4 class="text-xs font-semibold opacity-70 mb-1">EXTRACTED TEXT</h4>
            <p class="text-sm whitespace-pre-wrap">{@selected_story.ocr_text}</p>
          </div>

          <div class="flex items-center justify-between text-xs opacity-70">
            <span>Posted: {format_datetime(@selected_story.posted_at)}</span>
            <span :if={@selected_story.expires_at}>
              Expires: {format_datetime(@selected_story.expires_at)}
            </span>
          </div>
        </div>
        <.link patch={~p"/feed/stories"} class="modal-backdrop" aria-label="Close modal">
          <span class="sr-only">Close</span>
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    if connected?(socket) do
      Events.subscribe(user_id)
    end

    socket =
      socket
      |> assign(:profiles, Instagram.list_tracked_profiles(user_id))
      |> assign(:profile_id, "")
      |> assign(:limit, @page_size)
      |> assign(:selected_story, nil)
      |> load_stories()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :show, %{"id" => story_id}) do
    user_id = socket.assigns.current_scope.user.id
    story = Feed.get_story_for_user!(user_id, story_id)
    {:noreply, assign(socket, :selected_story, story)}
  end

  defp apply_action(socket, :index, _params) do
    {:noreply, assign(socket, :selected_story, nil)}
  end

  @impl true
  def handle_event("filter_profile", %{"profile_id" => profile_id}, socket) do
    socket =
      socket
      |> assign(:profile_id, profile_id)
      |> assign(:limit, @page_size)
      |> load_stories()

    {:noreply, socket}
  end

  def handle_event("load_more", _params, socket) do
    socket =
      socket
      |> update(:limit, &(&1 + @page_size))
      |> load_stories()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:instagram_event, %{type: :story_created}}, socket) do
    socket =
      socket
      |> assign(:profiles, Instagram.list_tracked_profiles(socket.assigns.current_scope.user.id))
      |> load_stories()

    {:noreply, socket}
  end

  def handle_info({:instagram_event, _event}, socket) do
    {:noreply, socket}
  end

  defp load_stories(socket) do
    user_id = socket.assigns.current_scope.user.id

    opts = [
      profile_id: socket.assigns.profile_id,
      limit: socket.assigns.limit,
      offset: 0
    ]

    stories = Feed.list_stories(user_id, opts)
    total = Feed.count_stories(user_id, opts)

    socket
    |> assign(:stories, stories)
    |> assign(:grouped_stories, group_by_day(stories))
    |> assign(:total_stories, total)
  end

  defp group_by_day(stories) do
    stories
    |> Enum.group_by(&day_label/1)
    |> Enum.sort_by(fn {_label, day_stories} -> day_sort_key(hd(day_stories)) end)
  end

  defp day_label(%{posted_at: nil}), do: "Unknown"
  defp day_label(%{posted_at: datetime}), do: DateTimeFormatter.long_date(datetime)

  defp day_sort_key(%{posted_at: nil}), do: 0
  defp day_sort_key(%{posted_at: datetime}), do: -DateTime.to_unix(datetime)

  defp profile_avatar_url(%{profile_pic_url: url}) when is_binary(url) and url != "", do: Media.to_url(url)
  defp profile_avatar_url(_profile), do: nil

  defp story_preview_url(%{screenshot_path: screenshot_path} = story)
       when is_binary(screenshot_path) and screenshot_path != "" do
    if local_static_path_exists?(screenshot_path) do
      Media.to_url(screenshot_path)
    else
      story_media_url(story)
    end
  end

  defp story_preview_url(story), do: story_media_url(story)

  defp story_media_url(%{media_url: media_url}) when is_binary(media_url) and media_url != "" do
    if browser_loadable_media_url?(media_url), do: media_url
  end

  defp story_media_url(_story), do: nil

  defp local_static_path_exists?(path) do
    cond do
      String.contains?(path, "priv/static/") ->
        [_, relative_path] = String.split(path, "priv/static/", parts: 2)
        File.exists?(path) or File.exists?(Path.join("priv/static", relative_path))

      String.starts_with?(path, "http") ->
        false

      String.starts_with?(path, "/") ->
        path
        |> String.trim_leading("/")
        |> then(&Path.join("priv/static", &1))
        |> File.exists?()

      true ->
        File.exists?(path) or File.exists?(Path.join("priv/static", path))
    end
  end

  defp browser_loadable_media_url?(url) do
    case URI.parse(url) do
      %{host: host} when is_binary(host) ->
        not String.ends_with?(host, "cdninstagram.com") and not String.ends_with?(host, "fbcdn.net")

      _ ->
        true
    end
  end

  defp format_datetime(datetime), do: DateTimeFormatter.datetime(datetime)
end
