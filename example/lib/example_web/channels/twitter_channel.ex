defmodule ExampleWeb.TwitterChannel do
  use Phoenix.Channel
  require Logger

  #def join("notification:*", %{"topics" => topics}, socket) do
  #  {:ok, socket
  #  |> assign(:topics, [])
  #  |> put_new_topics(topics)}
  #end

  def join("notification:" <> _user, _params, socket) do
    chan = "user_chan:" <> socket.assigns[:user_id]
    {:ok, socket 
    |> assign(:topics, [chan])
    |> put_new_topics([chan])}
  end

  def handle_in("watch", %{"topics" => topics}, socket) do
    Logger.info("engine, #{inspect socket.assigns[:user_id]} is watching #{inspect topics}")
    {:reply, :ok, put_new_topics(socket, topics)}
  end
  def handle_in("unwatch", %{"topics" => topics}, socket) do
    Logger.info("engine, #{inspect socket.assigns[:user_id]} is unwatching #{inspect topics}")
    Enum.map(topics, fn x -> ExampleWeb.Endpoint.unsubscribe(x) end)
    {:reply, :ok, socket}
  end
  def handle_in("twitter", %{"twitter" => msg}, socket) do
    source_user = socket.assigns[:user_id]
    Logger.info("Engine received twitter from #{source_user}: #{msg}")

    channel_list = parse_tweet(msg, source_user)

    Logger.info("dispatching to channels #{inspect channel_list}")
    
    Enum.map(channel_list, fn chan -> 
      Logger.info("down_msg is sending to channel #{inspect chan} with msg: #{inspect msg}")
      ExampleWeb.Endpoint.broadcast chan, "down_msg", %{"twitter" => msg, "source_user" => source_user}
      end)
    {:noreply, socket}
  end
  def handle_in(ev, msg, socket) do
    Logger.info("unexpected msg: #{inspect ev} <> #{inspect msg}")
    {:noreply, socket}
  end

  defp parse_tweet(str, user) do
    channel_list = ["user_chan:" <> user]
    channel_list = 
      if String.match?(str, ~r/@/) do
        user = str |> String.split("@", parts: 2) |> List.last |> String.split 
               |> List.first |> String.trim_trailing(".") 
               |> String.trim_trailing(",")
        ["user_chan:" <> user | channel_list] 
      else
        channel_list
      end
    channel_list = 
      if String.match?(str, ~r/#/) do
        tag = str |> String.split("#", parts: 2) |> List.last |> String.split 
              |> List.first |> String.trim_trailing(",") 
              |> String.trim_trailing(".")
        ["tag_chan:" <> tag | channel_list]
      else
        channel_list
      end
    Enum.uniq(channel_list)
  end

  defp put_new_topics(socket, topics) do
    Enum.reduce(topics, socket, fn topic, acc ->
      topics = acc.assigns.topics
      if topic in topics do
        acc
      else
        :ok = ExampleWeb.Endpoint.subscribe(topic)
        assign(acc, :topics, [topic | topics])
      end
    end)
  end

  alias Phoenix.Socket.Broadcast
  def handle_info(%Broadcast{topic: _, event: ev, payload: payload}, socket) do
    #Logger.info("hello, finally we reach here!")
      push socket, ev, payload
      {:noreply, socket}
  end
end
