defmodule Example.TwitterClient do
  @moduledoc false
  require Logger
  alias Phoenix.Channels.GenSocketClient
  @behaviour GenSocketClient

  def start_link(user_name) do
    GenSocketClient.start_link(
          __MODULE__,
          Phoenix.Channels.GenSocketClient.Transport.WebSocketClient,
          ["ws://localhost:4000/socket/websocket", user_name]
        )
  end

  def init([url, str]) do
    {:connect, url, [{"user_id", str}], 
      %{first_join: true, tw_ref: 1, user_name: str}}
  end

  # public api
  def push_tweet(client, msg) do
    Process.send(client, {:push_tweet, msg}, [])
  end
  def push_tweet(client, msg, at_user, tag) do
    msg = msg <> " @" <> at_user <> " #" <> tag
    push_tweet(client, msg)
  end

  def watch_topics(client, %{users: users, tags: tags}) do
    topics = Enum.reduce(users, [], fn(t, acc) -> ["user_chan:"<>t | acc] end)
    topics = Enum.reduce(tags, topics, fn(t, acc) -> ["tag_chan:"<>t | acc] end)
    Process.send(client, {:watch, topics}, [])
  end

  def watch_users(client, users) do
    watch_topics(client, %{users: users, tags: []})
  end

  def watch_tags(client, tags) do
    watch_topics(client, %{users: [], tags: tags})
  end

  def unwatch_topics(client, %{users: users, tags: tags}) do
    topics = Enum.reduce(users, [], fn(t, acc) -> ["user_chan:"<>t | acc] end)
    topics = Enum.reduce(tags, topics, fn(t, acc) -> ["tag_chan:"<>t | acc] end)
    Process.send(client, {:unwatch, topics}, [])
  end

  def unwatch_users(client, users) do
    unwatch_topics(client, %{users: users, tags: []})
  end

  def unwatch_tags(client, tags) do
    unwatch_topics(client, %{users: [], tags: tags})
  end

  # handlers
  def handle_connected(transport, state) do
    Logger.info("client connected to server!")
    GenSocketClient.join(transport, "notification:"<>state.user_name)
    {:ok, state}
  end

  def handle_disconnected(reason, state) do
    Logger.error("disconnected: #{inspect reason}")
    Process.send_after(self(), :connect, :timer.seconds(1))
    {:ok, state}
  end

  def handle_joined(topic, _payload, _transport, state) do
    Logger.info("joined the topic #{topic}")

    if state.first_join do
      watch_users(self(), [state.user_name])
    end

    #:timer.send_interval(:timer.seconds(1), self(), :push_tweet)
    {:ok, %{state | first_join: false, tw_ref: 1}}
  end

  def handle_join_error(topic, payload, _transport, state) do
    Logger.error("join error on the topic #{topic}: #{inspect payload}")
    {:ok, state}
  end

  def handle_channel_closed(topic, payload, _transport, state) do
    Logger.error("disconnected from the topic #{topic}: #{inspect payload}")
    Process.send_after(self(), {:join, topic}, :timer.seconds(1))
    {:ok, state}
  end

  def handle_message(topic, event, payload, _transport, state) do
    Logger.warn("client #{inspect state.user_name} received message on topic with content:#{inspect payload}")
    {:ok, state}
  end

  def handle_reply("ping", _ref, %{"status" => "ok"} = payload, _transport, state) do
    #Logger.info("server pong ##{payload["response"]["tw_ref"]}")
    Logger.info("received reply from engine: #{payload}")
    {:ok, state}
  end
  def handle_reply(topic, _ref, payload, _transport, state) do
    Logger.warn("reply on topic #{topic}: #{inspect payload}")
    {:ok, state}
  end

  def handle_info({:push_tweet, msg}, transport, state) do
    chan_str = "notification:" <> state.user_name
    #Logger.info("on client, trying to push tweet: #{msg}")
    GenSocketClient.push(transport, chan_str, "twitter", 
                         %{"twitter" => msg})
    {:ok, state}
  end
  def handle_info({:watch, topics}, transport, state) do
    chan_str = "notification:" <> state.user_name
    Logger.info("on client, #{inspect state.user_name} is trying to watch #{inspect topics}")
    GenSocketClient.push(transport, chan_str, "watch", 
                         %{"topics" => topics})
    {:ok, state}
  end
  def handle_info({:unwatch, topics}, transport, state) do
    #Logger.info("on client, unwatch is called")
    chan_str = "notification:" <> state.user_name
    GenSocketClient.push(transport, chan_str, "unwatch", 
                         %{"topics" => topics})
    {:ok, state}
  end
  def handle_info(:connect, _transport, state) do
    Logger.info("connecting")
    {:connect, state}
  end
  def handle_info({:join, topic}, transport, state) do
    Logger.info("joining the topic #{topic} ...")
    case GenSocketClient.join(transport, topic) do
      {:error, reason} ->
        Logger.error("error joining the topic #{topic}: #{inspect reason}")
        Process.send_after(self(), {:join, topic}, :timer.seconds(1))
      {:ok, _ref} -> :ok
    end
    {:ok, state}
  end
  def handle_info(:ping_server, transport, state) do
    Logger.info("sending ping ##{state.tw_ref}")
    GenSocketClient.push(transport, "ping", "ping", %{tw_ref: state.tw_ref})
    {:ok, %{state | tw_ref: state.tw_ref + 1}}
  end
  def handle_info(message, _transport, state) do
    Logger.warn("Unhandled message #{inspect message}")
    {:ok, state}
  end
end
