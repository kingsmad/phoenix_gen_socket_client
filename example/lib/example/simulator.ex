defmodule Example.Simulator do
  use GenServer, restart: :transient
  require Logger
  alias Example.TwitterClient
  @tag_num 10 
  
  def start_link() do
    GenServer.start_link(__MODULE__, [5])
  end

  def init([client_num]) do
    corpus = File.stream!("in.txt") |> 
               Stream.map(&String.trim_trailing/1) |> Enum.to_list

    names = Enum.reduce(1..client_num, [], fn (i, acc) ->
      ["jolly" <> Integer.to_string(i) | acc]
    end)

    tags = Enum.reduce(1..@tag_num, [], fn (i, acc) ->
      ["Trunald_dump_tag" <> Integer.to_string(i) | acc]
    end)

    run_client(client_num, 10)

    {:ok, %{corpus: corpus, names: names, tags: tags, clients: []}}
  end

  def run_client(client_num, _speed) do
    GenServer.cast(self(), {:run_client, client_num})
  end

  def handle_cast({:run_client, client_num}, state) do
    clients = Enum.reduce(1..client_num, [], fn (i, acc) -> 
      {:ok, c} = TwitterClient.start_link("jolly_" <> Integer.to_string(i))
      [c | acc] 
    end)
    Logger.info("in run_client, clients are: #{inspect clients}")

    :timer.send_interval(:timer.seconds(1), self(), {:send_random_tweet, 10})

    {:noreply, %{state | clients: clients}}
  end

  def handle_info({:send_random_tweet, num}, state) do
    Logger.info("send_random_tweet invoked...")
    clients = Enum.take_random(state.clients, num)

    # randomly watch some channels
    Enum.map(clients, fn c -> 
      rd_num = Enum.random(1..length(state.names))
      TwitterClient.watch_users(c, Enum.take_random(state.names, rd_num))
    end)

    # randomly send some twitters
    Enum.map(clients, fn c -> 
      msgs = Enum.take_random(state.corpus, 
                              Enum.random(1..length(state.corpus)))
      Enum.map(msgs, fn msg ->
        msg = 
          if :rand.uniform(2) == 1 do
            msg <> " @" <> Enum.random(state.names) <> " "
          else
            msg
          end
        msg = 
          if :rand.uniform(2) == 1 do
            msg <> " #" <> Enum.random(state.tags) <> " "
          else
            msg
          end
        # Logger.info("on client side, #{inspect c} sending #{msg}")
        TwitterClient.push_tweet(c, msg)
      end)
    end)
    {:noreply, state}
  end

end
