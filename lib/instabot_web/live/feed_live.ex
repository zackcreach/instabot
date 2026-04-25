defmodule InstabotWeb.FeedLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Instagram.Events
  alias Instabot.Instagram.Feed
  alias InstabotWeb.DateTimeFormatter

  @html_entities [
    {"&amp;", "&"},
    {"&quot;", "\""},
    {"&#39;", "'"},
    {"&apos;", "'"},
    {"&lt;", "<"},
    {"&gt;", ">"},
    {"&nbsp;", " "}
  ]
  @page_size Feed.default_limit()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Feed</h1>
          <.link navigate={~p"/feed/stories"} class="btn btn-ghost btn-sm">
            <.icon name="hero-film" class="size-4" /> Stories
          </.link>
        </div>

        <div class="flex flex-col sm:flex-row gap-3">
          <form id="profile-filter" phx-change="filter_profile" class="sm:w-64">
            <select
              name="profile_id"
              class="select select-bordered w-full"
            >
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

          <form id="search-form" phx-change="search" class="flex-1">
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Search captions and hashtags"
              phx-debounce="300"
              class="input input-bordered w-full"
            />
          </form>
        </div>

        <div :if={@posts == []} class="text-center py-16 opacity-70">
          <.icon name="hero-photo" class="size-12 opacity-30 mx-auto mb-4" />
          <h3 class="text-lg font-semibold mb-2">
            {empty_title(@search, @profile_id)}
          </h3>
          <p class="text-sm">
            {empty_subtitle(@search, @profile_id, @profiles)}
          </p>
        </div>

        <div
          :if={@posts != []}
          id="posts-grid"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
        >
          <.link
            :for={post <- @posts}
            id={"post-#{post.id}"}
            patch={~p"/feed/posts/#{post.id}"}
            class="card bg-base-100 shadow hover:shadow-lg transition-shadow cursor-pointer"
          >
            <figure class="aspect-square bg-base-300 overflow-hidden">
              <img
                :if={thumbnail_for(post)}
                src={thumbnail_for(post)}
                alt={display_caption(post.caption) || "Instagram post"}
                class="w-full h-full object-cover"
              />
              <div :if={!thumbnail_for(post)} class="flex items-center justify-center w-full h-full">
                <.icon name="hero-photo" class="size-10 opacity-30" />
              </div>
            </figure>
            <div class="card-body p-4">
              <div class="flex items-center gap-2">
                <div class={[
                  "avatar",
                  is_nil(profile_avatar_url(post.tracked_profile)) && "placeholder"
                ]}>
                  <div class="bg-neutral text-neutral-content w-6 rounded-full">
                    <img
                      :if={profile_avatar_url(post.tracked_profile)}
                      src={profile_avatar_url(post.tracked_profile)}
                      alt={post.tracked_profile.instagram_username}
                    />
                    <span :if={is_nil(profile_avatar_url(post.tracked_profile))} class="text-xs">
                      {String.first(post.tracked_profile.instagram_username) |> String.upcase()}
                    </span>
                  </div>
                </div>
                <span class="text-sm font-medium truncate">
                  @{post.tracked_profile.instagram_username}
                </span>
                <span class="text-xs opacity-50 ml-auto shrink-0 text-right">
                  {DateTimeFormatter.relative(post_display_datetime(post))}
                </span>
              </div>
              <p :if={display_caption(post.caption)} class="text-sm line-clamp-3 mt-1">
                {display_caption(post.caption)}
              </p>
            </div>
          </.link>
        </div>

        <div
          :if={@posts != [] and length(@posts) < @total_posts}
          id="posts-sentinel"
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

      <div :if={@selected_post} id="post-modal" class="modal modal-open" role="dialog">
        <div class="modal-box max-w-4xl">
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-2">
              <div class={[
                "avatar",
                is_nil(profile_avatar_url(@selected_post.tracked_profile)) && "placeholder"
              ]}>
                <div class="bg-neutral text-neutral-content w-8 rounded-full">
                  <img
                    :if={profile_avatar_url(@selected_post.tracked_profile)}
                    src={profile_avatar_url(@selected_post.tracked_profile)}
                    alt={@selected_post.tracked_profile.instagram_username}
                  />
                  <span
                    :if={is_nil(profile_avatar_url(@selected_post.tracked_profile))}
                    class="text-xs"
                  >
                    {String.first(@selected_post.tracked_profile.instagram_username)
                    |> String.upcase()}
                  </span>
                </div>
              </div>
              <div>
                <div class="font-semibold">@{@selected_post.tracked_profile.instagram_username}</div>
                <div class="text-xs opacity-50">
                  {DateTimeFormatter.relative(post_display_datetime(@selected_post))}
                </div>
              </div>
            </div>
            <.link patch={~p"/feed"} class="btn btn-ghost btn-sm btn-circle" aria-label="Close">
              <.icon name="hero-x-mark" class="size-5" />
            </.link>
          </div>

          <div
            id={"lightbox-#{@selected_post.id}-#{@selected_image_index}"}
            phx-hook=".Lightbox"
            class="relative aspect-square bg-base-300 rounded overflow-hidden mb-4 select-none"
          >
            <img
              :if={current_image(@selected_post, @selected_image_index)}
              src={current_image(@selected_post, @selected_image_index)}
              alt={display_caption(@selected_post.caption) || "Instagram post"}
              class="w-full h-full object-contain pointer-events-none"
            />
            <div
              :if={image_count(@selected_post) > 1}
              class="absolute inset-0 flex items-center justify-between p-2 pointer-events-none"
            >
              <button
                phx-click="prev_image"
                disabled={@selected_image_index == 0}
                class="btn btn-circle btn-sm pointer-events-auto"
                aria-label="Previous image"
              >
                <.icon name="hero-chevron-left" class="size-4" />
              </button>
              <button
                phx-click="next_image"
                disabled={@selected_image_index >= image_count(@selected_post) - 1}
                class="btn btn-circle btn-sm pointer-events-auto"
                aria-label="Next image"
              >
                <.icon name="hero-chevron-right" class="size-4" />
              </button>
            </div>
            <div
              :if={image_count(@selected_post) > 1}
              class="absolute bottom-2 left-1/2 -translate-x-1/2 bg-base-100/80 rounded-full px-3 py-1 text-xs"
            >
              {@selected_image_index + 1} / {image_count(@selected_post)}
            </div>
          </div>

          <p :if={display_caption(@selected_post.caption)} class="text-sm whitespace-pre-wrap mb-3">
            {display_caption(@selected_post.caption)}
          </p>

          <div :if={@selected_post.hashtags != []} class="flex flex-wrap gap-1 mb-3">
            <span
              :for={hashtag <- @selected_post.hashtags}
              class="badge badge-ghost badge-sm"
            >
              #{hashtag}
            </span>
          </div>

          <div class="flex items-center justify-between text-xs opacity-70">
            <span>{format_datetime(post_display_datetime(@selected_post))}</span>
            <.link
              :if={@selected_post.permalink}
              href={@selected_post.permalink}
              target="_blank"
              rel="noopener noreferrer"
              class="link"
            >
              View on Instagram
            </.link>
          </div>
        </div>
        <.link patch={~p"/feed"} class="modal-backdrop" aria-label="Close modal">
          <span class="sr-only">Close</span>
        </.link>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Lightbox">
        export default {
          mounted() {
            this.scale = 1;
            this.translateX = 0;
            this.translateY = 0;
            this.dragging = false;
            this.lastX = 0;
            this.lastY = 0;
            this.initialPinchDistance = null;
            this.initialPinchScale = 1;

            this.img = this.el.querySelector("img");
            if (!this.img) return;

            this.el.style.cursor = "zoom-in";
            this.el.style.touchAction = "none";

            this.handleWheel = (event) => {
              event.preventDefault();
              const delta = event.deltaY > 0 ? -0.2 : 0.2;
              this.zoom(Math.max(1, Math.min(5, this.scale + delta)));
            };

            this.handleDblClick = () => {
              if (this.scale > 1) {
                this.zoom(1);
              } else {
                this.zoom(2.5);
              }
            };

            this.handleMouseDown = (event) => {
              if (this.scale <= 1) return;
              event.preventDefault();
              this.dragging = true;
              this.lastX = event.clientX;
              this.lastY = event.clientY;
              this.el.style.cursor = "grabbing";
            };

            this.handleMouseMove = (event) => {
              if (!this.dragging) return;
              this.translateX += event.clientX - this.lastX;
              this.translateY += event.clientY - this.lastY;
              this.lastX = event.clientX;
              this.lastY = event.clientY;
              this.clampAndApply();
            };

            this.handleMouseUp = () => {
              this.dragging = false;
              this.el.style.cursor = this.scale > 1 ? "grab" : "zoom-in";
            };

            this.handleTouchStart = (event) => {
              if (event.touches.length === 2) {
                this.initialPinchDistance = this.pinchDistance(event.touches);
                this.initialPinchScale = this.scale;
              } else if (event.touches.length === 1 && this.scale > 1) {
                this.dragging = true;
                this.lastX = event.touches[0].clientX;
                this.lastY = event.touches[0].clientY;
              }
            };

            this.handleTouchMove = (event) => {
              event.preventDefault();
              if (event.touches.length === 2 && this.initialPinchDistance) {
                const distance = this.pinchDistance(event.touches);
                const ratio = distance / this.initialPinchDistance;
                this.zoom(Math.max(1, Math.min(5, this.initialPinchScale * ratio)));
              } else if (event.touches.length === 1 && this.dragging) {
                this.translateX += event.touches[0].clientX - this.lastX;
                this.translateY += event.touches[0].clientY - this.lastY;
                this.lastX = event.touches[0].clientX;
                this.lastY = event.touches[0].clientY;
                this.clampAndApply();
              }
            };

            this.handleTouchEnd = (event) => {
              if (event.touches.length < 2) this.initialPinchDistance = null;
              if (event.touches.length === 0) this.dragging = false;
            };

            this.el.addEventListener("wheel", this.handleWheel, { passive: false });
            this.el.addEventListener("dblclick", this.handleDblClick);
            this.el.addEventListener("mousedown", this.handleMouseDown);
            window.addEventListener("mousemove", this.handleMouseMove);
            window.addEventListener("mouseup", this.handleMouseUp);
            this.el.addEventListener("touchstart", this.handleTouchStart, { passive: true });
            this.el.addEventListener("touchmove", this.handleTouchMove, { passive: false });
            this.el.addEventListener("touchend", this.handleTouchEnd);
          },

          destroyed() {
            window.removeEventListener("mousemove", this.handleMouseMove);
            window.removeEventListener("mouseup", this.handleMouseUp);
          },

          zoom(newScale) {
            this.scale = newScale;
            if (this.scale <= 1) {
              this.translateX = 0;
              this.translateY = 0;
            }
            this.el.style.cursor = this.scale > 1 ? "grab" : "zoom-in";
            this.clampAndApply();
          },

          clampAndApply() {
            if (this.scale <= 1) {
              this.translateX = 0;
              this.translateY = 0;
            } else {
              const rect = this.el.getBoundingClientRect();
              const maxX = (rect.width * (this.scale - 1)) / 2;
              const maxY = (rect.height * (this.scale - 1)) / 2;
              this.translateX = Math.max(-maxX, Math.min(maxX, this.translateX));
              this.translateY = Math.max(-maxY, Math.min(maxY, this.translateY));
            }
            this.img.style.transform =
              `scale(${this.scale}) translate(${this.translateX / this.scale}px, ${this.translateY / this.scale}px)`;
          },

          pinchDistance(touches) {
            const dx = touches[0].clientX - touches[1].clientX;
            const dy = touches[0].clientY - touches[1].clientY;
            return Math.sqrt(dx * dx + dy * dy);
          }
        };
      </script>
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
      |> assign(:search, "")
      |> assign(:limit, @page_size)
      |> assign(:selected_post, nil)
      |> assign(:selected_image_index, 0)
      |> load_posts()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :show, %{"id" => post_id}) do
    user_id = socket.assigns.current_scope.user.id
    post = Feed.get_post_for_user!(user_id, post_id)

    socket =
      socket
      |> assign(:selected_post, post)
      |> assign(:selected_image_index, 0)

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    {:noreply, assign(socket, :selected_post, nil)}
  end

  @impl true
  def handle_event("filter_profile", %{"profile_id" => profile_id}, socket) do
    socket =
      socket
      |> assign(:profile_id, profile_id)
      |> assign(:limit, @page_size)
      |> load_posts()

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> assign(:limit, @page_size)
      |> load_posts()

    {:noreply, socket}
  end

  def handle_event("load_more", _params, socket) do
    socket =
      socket
      |> update(:limit, &(&1 + @page_size))
      |> load_posts()

    {:noreply, socket}
  end

  def handle_event("prev_image", _params, socket) do
    {:noreply, update(socket, :selected_image_index, fn index -> max(index - 1, 0) end)}
  end

  def handle_event("next_image", _params, socket) do
    max_index = image_count(socket.assigns.selected_post) - 1
    {:noreply, update(socket, :selected_image_index, fn index -> min(index + 1, max_index) end)}
  end

  @impl true
  def handle_info({:instagram_event, %{type: :post_created}}, socket) do
    socket =
      socket
      |> assign(:profiles, Instagram.list_tracked_profiles(socket.assigns.current_scope.user.id))
      |> load_posts()

    {:noreply, socket}
  end

  def handle_info({:instagram_event, _event}, socket) do
    {:noreply, socket}
  end

  defp load_posts(socket) do
    user_id = socket.assigns.current_scope.user.id

    opts = [
      profile_id: socket.assigns.profile_id,
      search: socket.assigns.search,
      limit: socket.assigns.limit,
      offset: 0
    ]

    socket
    |> assign(:posts, Feed.list_posts(user_id, opts))
    |> assign(:total_posts, Feed.count_posts(user_id, opts))
  end

  defp thumbnail_for(%{post_images: [%{local_path: path} | _]}) when is_binary(path), do: Instabot.Media.to_url(path)

  defp thumbnail_for(%{media_urls: [url | _]}) when is_binary(url), do: url

  defp thumbnail_for(_post), do: nil

  defp image_count(%{post_images: images}) when is_list(images) and images != [], do: length(images)
  defp image_count(%{media_urls: urls}) when is_list(urls), do: length(urls)
  defp image_count(_post), do: 0

  defp current_image(%{post_images: images}, index) when is_list(images) and images != [] do
    case Enum.at(images, index) do
      %{local_path: path} -> Instabot.Media.to_url(path)
      _ -> nil
    end
  end

  defp current_image(%{media_urls: urls}, index) when is_list(urls), do: Enum.at(urls, index)
  defp current_image(_post, _index), do: nil

  defp profile_avatar_url(%{profile_pic_url: url}) when is_binary(url) and url != "", do: Instabot.Media.to_url(url)
  defp profile_avatar_url(_profile), do: nil

  defp post_display_datetime(%{posted_at: %DateTime{} = posted_at}), do: posted_at
  defp post_display_datetime(%{inserted_at: inserted_at}), do: inserted_at

  defp display_caption(nil), do: nil

  defp display_caption(caption) when is_binary(caption) do
    caption
    |> decode_html_entities()
    |> trim_caption_prefix()
    |> String.trim()
  end

  defp trim_caption_prefix(caption) do
    cond do
      String.contains?(caption, "&quot;") ->
        caption
        |> String.split("&quot;", parts: 2)
        |> List.last()
        |> trim_caption_suffix()

      String.contains?(caption, "\"") ->
        caption
        |> String.split("\"", parts: 2)
        |> List.last()
        |> trim_caption_suffix()

      true ->
        caption
    end
  end

  defp trim_caption_suffix(caption) do
    caption
    |> String.trim()
    |> String.replace(~r/"\.?$/u, "")
  end

  defp decode_html_entities(text) do
    Enum.reduce(@html_entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  defp empty_title("", ""), do: "No posts yet"
  defp empty_title(_search, _profile_id), do: "No matches"

  defp empty_subtitle("", "", []), do: "Add tracked profiles and scrape them to populate your feed."

  defp empty_subtitle("", "", _profiles),
    do: "Run a scrape from the dashboard to pull in posts from your tracked profiles."

  defp empty_subtitle(_search, _profile_id, _profiles), do: "Try clearing the filter or search term."

  defp format_datetime(datetime), do: DateTimeFormatter.long_datetime(datetime)
end
