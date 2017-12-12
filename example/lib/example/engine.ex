defmodule Engine do
  use GenServer, restart: :transient 

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, lfd} = :gen_tcp.listen(6667, [:binary, {:packet, 0}, {:active, false}, {:reuseaddr, true}])

    IO.puts "server started, accepting..."

    IO.puts "engine pid is: "
    IO.inspect self()

    self_pid = self()
    spawn(fn -> accept(self_pid, lfd) end) 

    {:ok, %{"mailbox" => %{}, "sid2mailbox" => %{}, "tag2mailbox" => %{ }, 
      "listen_fd" => lfd, "online_sids" => MapSet.new(), "sid2sock" => %{ }}}
  end

  def print_state(self) do
    GenServer.call(self, {:print_state})
  end

  def accept(engine, lfd) do
    {:ok, sock} = :gen_tcp.accept lfd
    IO.puts "dected client connected...\n"
    spawn(fn -> serve(engine, sock) end)
    accept(engine, lfd)
  end

  def register_sock(engine, sid, sock) do
    GenServer.cast(engine, {:register_sock, {sid, sock}})
  end

  def serve(engine, sock) do
    #IO.puts "in serve loop, engine is: "
    #IO.inspect engine
     case :gen_tcp.recv(sock, 0) do
       {:tcp_closed, _} -> 
         Process.exit(self(), :kill)
       {:error, _} ->
         IO.puts "network error detected\n"
         Process.exit(self(), :kill)
       {:ok, msg} ->
         IO.puts "Received msg: " 
         IO.inspect msg
         IO.puts "\n"
         case msg |> String.split |> List.first do
           "cmd" ->
             {_, para_list} = msg |> String.split |> List.pop_at(0)
             {cmd, para_list} = para_list |> List.pop_at(0)
             {user_name, para_list} = para_list |> List.pop_at(0)
             case cmd do
               "register" ->
                 register_sock(engine, user_name, sock)
                 register(engine, user_name)
               "offline" ->
                 offline(engine, user_name)
               "online" ->
                 online(engine, user_name)
               "subscribe" ->
                 {other_user, _} = para_list |> List.pop_at(0)
                 subscribe(engine, user_name, other_user)
               _ ->
                 IO.puts "wrong client msg\n"
             end
           _ ->
             IO.puts "hello, we are redirecting msg..\n"
             receive_tweet(engine, msg)
         end
     end
     IO.puts "continue server...\n"
    serve(engine, sock)
  end

  def online(engine, user_name) do
    GenServer.cast(engine, {:online, user_name})
  end

  def offline(engine, user_name) do
    GenServer.cast(engine, {:offline, user_name})
  end

  def register(engine, user_name) do
    IO.puts "registering... user_name is: " <> user_name <> "\n"
    GenServer.cast(engine, {:register, user_name})
  end

  def receive_tweet(engine, str) do
    IO.puts "receive_tweet is called\n"
    IO.inspect engine 
    GenServer.cast(engine, {:receive_tweet, str})
  end

  def push_mail(engine, sid) do
    GenServer.cast(engine, {:push_mail, sid})
  end

  def subscribe(engine, user_name, other_user) do
    if other_user != nil and user_name != nil do
      GenServer.cast(engine, {:subscribe, {user_name, other_user}}) 
    end
  end

  def handle_cast({:push_mail, sid}, state) do
    IO.puts "Pushing mails..."
    list = state |> Map.get("mailbox") |> Map.get(sid)
    mailbox = state |> Map.get("mailbox") |> Map.put(sid, [])
    state = Map.put(state, "mailbox", mailbox)

    sock = state |> Map.get("sid2sock") |> Map.get(sid)
    IO.puts "pushing mail to sockets..." 
    data = Enum.reduce(list, "", fn (str, acc) -> acc <> "\n" <> str end)
    :gen_tcp.send sock, data 
    {:noreply, state}
  end
  
  def handle_cast({:online, user_name}, state) do
    online_sids = state |> Map.get("online_sids") |> MapSet.put(user_name)
    {:noreply, state |> Map.put("online_sids", online_sids)}
  end

  def handle_cast({:offline, user_name}, state) do
    online_sids = state |> Map.get("online_sids") |> MapSet.delete(user_name)
    {:noreply, state |> Map.put("online_sids", online_sids)}
  end

  def handle_cast({:subscribe, {user_name, other_user}}, state) do
    sid2mailbox = state |> Map.get("sid2mailbox")
    tmp = sid2mailbox |> Map.get(other_user)
    tmp = 
      if tmp == nil do
        MapSet.new()
      else
        tmp
      end
      
    #sid_set = sid2mailbox |> Map.get(other_user) |> MapSet.put(user_name)
    sid_set = tmp |> MapSet.put(user_name)
    sid2mailbox = sid2mailbox |> Map.put(other_user, sid_set)
    state = state |> Map.put("sid2mailbox", sid2mailbox)
    {:noreply, state}
  end

  def handle_cast({:register, user_name}, state) do
    mailbox = state |> Map.get("mailbox") |> Map.put(user_name, ["System: welcome to tweet"])
    sid_set = MapSet.new() |> MapSet.put(user_name)
    sid2mailbox = state |> Map.get("sid2mailbox") |> Map.put(user_name, sid_set)
    state = state |> Map.put("mailbox", mailbox) |> Map.put("sid2mailbox", sid2mailbox) 
    {:noreply, state}
  end

  def handle_cast({:register_sock, {sid, sock}}, state) do
    sid2sock = state |> Map.get("sid2sock") |> Map.put(sid, sock)
    {:noreply, state |> Map.put("sid2sock", sid2sock)}
  end

  def handle_cast({:receive_tweet, str}, state) do
    #IO.puts "handle_cast : receive_tweet\n str is: " <> str <> "\n"
    user_name = String.split(str, ":") |> List.first |> String.trim_trailing(":")
    sid2mailbox = Map.get(state, "sid2mailbox")

    state = 
      case Map.get(sid2mailbox, user_name) do
        nil ->
          state
        subscribers ->
          # add str to each of the subscribers of this user
          mailbox = state |> Map.get("mailbox")
          mailbox = Enum.reduce(subscribers, mailbox, fn (sid, acc) -> 
                    list = acc |> Map.get(sid); list = [str | list]; acc |> Map.put(sid, list); end)

          # handle # symbol
          mailbox = 
            if String.match?(str, ~r/#/) do
              tag = str |> String.split("#", parts: 2) |> List.last |> String.split 
                    |> List.first |> String.trim_trailing(",") |> String.trim_trailing(".")
              sids = state |> Map.get("tag2mailbox") |> Map.get(tag)
              if sids == nil do
                mailbox
              else
                Enum.reduce(sids, state |> Map.get("mailbox"), fn (sid, acc) -> 
                  list = acc |> Map.get(sid); list = [str | list]; acc |> Map.put(sid, list); end)
              end
            else
              mailbox
            end

          # handle @ symbol
          mailbox = 
            if String.match?(str, ~r/@/) do
              user = str |> String.split("@", parts: 2) |> List.last |> String.split 
                     |> List.first |> String.trim_trailing(".") |> String.trim_trailing(",")
              msg_box = state |> Map.get("mailbox") |> Map.get(user)
              msg_box = [str | msg_box] 
              mailbox |> Map.put(user, msg_box)
            else
              mailbox
            end
          state |> Map.put("mailbox", mailbox)
      end

    online_sids = state |> Map.get("online_sids")
    if sid2mailbox |> Map.get(user_name) != nil do
      Enum.map(sid2mailbox |> Map.get(user_name), fn sid -> if MapSet.member?(online_sids, sid), do: (push_mail(self(), sid)) end)
    end
    {:noreply, state}
  end
            
  def handle_call({:print_state}, _from, state) do
    {:reply, state, state}
  end
end
