defmodule InstabotWeb.StoriesLive do
  @moduledoc false
  use InstabotWeb, :live_view

  alias Instabot.Instagram
  alias Instabot.Instagram.Feed

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
                    :if={story.screenshot_path}
                    src={Instabot.Media.to_url(story.screenshot_path)}
                    alt="Story screenshot"
                    class="w-full h-full object-cover"
                  />
                  <div
                    :if={!story.screenshot_path}
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
                    <span class="text-xs opacity-50 ml-auto">
                      {relative_time(story.posted_at)}
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
        <div class="modal-box max-w-2xl">
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
                <div class="text-xs opacity-50">{relative_time(@selected_story.posted_at)}</div>
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
            phx-hook=".Lightbox"
            class="aspect-[9/16] bg-base-300 rounded overflow-hidden mb-4 max-h-[60vh] mx-auto select-none"
          >
            <img
              :if={@selected_story.screenshot_path}
              src={Instabot.Media.to_url(@selected_story.screenshot_path)}
              alt="Story screenshot"
              class="w-full h-full object-contain pointer-events-none"
            />
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
  defp day_label(%{posted_at: datetime}), do: Calendar.strftime(datetime, "%B %d, %Y")

  defp day_sort_key(%{posted_at: nil}), do: 0
  defp day_sort_key(%{posted_at: datetime}), do: -DateTime.to_unix(datetime)

  defp profile_avatar_url(%{profile_pic_url: url}) when is_binary(url) and url != "", do: Instabot.Media.to_url(url)
  defp profile_avatar_url(_profile), do: nil

  defp relative_time(nil), do: "just now"

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
end
