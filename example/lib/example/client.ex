defmodule Client do
  use GenServer, restart: :transient
  
  def start_link(user_name, speed_per_sec, corpus, all_user_names) do
    GenServer.start_link(__MODULE__, [user_name, speed_per_sec, 
                                      corpus, all_user_names])
  end

  def init([user_name, speed_per_sec, corpus, all_user_names]) do
    opts = [:binary, active: false]
    socket = 
      case :gen_tcp.connect('localhost', 6667, opts) do
        {:ok, socket} ->
          IO.puts "connected to server"
          spawn_link(fn -> serve(socket) end)
          socket
        _ ->
          IO.puts "connection error to server!"
          nil
      end

    {:ok, %{"socket" => socket, "speed_per_sec" => speed_per_sec, 
      "user_name" => user_name, "corpus" => corpus, "all_user_names" => all_user_names}}
  end

  def serve(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:tcp_closed, _} -> 
        IO.puts "tcp is closed\n"
        Process.exit(self(), :kill)
      {:error, _} ->
        IO.puts "error detected"
        Process.exit(self(), :kill)
      {:ok, msg} ->
        IO.puts "new tweets received from engine\n" 
        IO.inspect msg 
        IO.puts "\n"
    end
    serve(socket)
  end

  
  def init_action(client) do
    GenServer.cast(client, {:init_action, client}) 
  end

  def random_action(client) do
    GenServer.cast(client, {:random_action, client}) end

  def register(client) do
    GenServer.cast(client, {:register})
  end

  def online(client) do
    GenServer.cast(client, {:online})
  end

  def offline(client) do
    GenServer.cast(client, {:offline})
  end

  def send_tweet(client, str) do
    GenServer.cast(client, {:send_tweet, str})
  end

  def subscribe(client, upper_user) do
    GenServer.cast(client, {:subscribe, upper_user})
  end

  def retweet(client, str) do
    GenServer.cast(client, {:retweet, str})
  end

  def print_state(self) do
    GenServer.call(self, {:print_state})
  end

  def handle_cast({:init_action, client}, state) do
    register(client)
    online(client)

    users = state |> Map.get("all_user_names") |> Enum.take_random(10)
    Enum.map(users, fn sid -> subscribe(client, sid) end)
    {:noreply, state}
  end

  def handle_cast({:random_action, client}, state) do
    str = state |> Map.get("corpus") |> Enum.random
    at_user = state |> Map.get("all_user_names") |> Enum.random

    if Enum.random(1..2) == 1 do
        send_tweet(client, str <> " @" <> at_user)
    end

    #if Enum.random(1..100) == 1 do
    #  offline(client)
    #else
    #  online(client)
    #end
    {:noreply, state}
  end

  def handle_cast({:online}, state) do
    sock = Map.get(state, "socket")
    user_name = Map.get(state, "user_name")

    IO.puts "client " <> user_name <> " is comming online..."

    data = "cmd" <> " " <> "online" <> " " <> user_name
    :gen_tcp.send sock, data
    {:noreply, state}
  end

  def handle_cast({:offline}, state) do
    sock = Map.get(state, "socket")
    user_name = Map.get(state, "user_name")

    IO.puts "client " <> user_name <> " is going offline..."

    data = "cmd " <> "offline " <> user_name
    :gen_tcp.send sock, data
    {:noreply, state}
  end

  def handle_cast({:register}, state) do
    sock = Map.get(state, "socket")
    user_name = Map.get(state, "user_name")
    data = "cmd" <> " " <> "register" <> " " <> user_name
    :gen_tcp.send sock, data
    {:noreply, state}
  end

  def handle_cast({:send_tweet, str}, state) do
    sock = Map.get(state, "socket")
    user_name = Map.get(state, "user_name")
    data = user_name <> ": " <> str
    :gen_tcp.send sock, data 
    {:noreply, state}
  end

  def handle_cast({:subscribe, upper_user}, state) do
    sock = Map.get(state, "socket")
    user_name = Map.get(state, "user_name")
    data = "cmd " <> "subscribe " <> user_name <> " " <> upper_user <> " "
    :gen_tcp.send sock, data
    {:noreply, state}
  end

  def handle_cast({:retweet, str}, state) do
    sock = Map.get(state, "socket")
    user_name = Map.get(state, "user_name")
    data = "cmd " <> "retweet " <> user_name <> ": " <> str
    :gen_tcp.send sock, data
    {:noreply, state}
  end

  def handle_call({:print_state}, _from, state) do
    {:reply, state, state}
  end
end

