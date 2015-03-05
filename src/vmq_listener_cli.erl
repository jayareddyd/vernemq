%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(vmq_listener_cli).
-export([register_server_cli/0]).

register_server_cli() ->
    clique:register_usage(["vmq-admin", "listener"], vmq_listener_usage()),
    clique:register_usage(["vmq-admin", "listener", "start"],
                          vmq_listener_start_usage()),
    clique:register_usage(["vmq-admin", "listener", "stop"],
                          vmq_listener_stop_usage()),
    clique:register_usage(["vmq-admin", "listener", "delete"],
                          vmq_listener_delete_usage()),
    clique:register_usage(["vmq-admin", "listener", "restart"],
                          vmq_listener_restart_usage()),
    vmq_listener_start_cmd(),
    vmq_listener_stop_cmd(),
    vmq_listener_delete_cmd(),
    vmq_listener_restart_cmd(),
    vmq_listener_show_cmd().

vmq_listener_start_cmd() ->
    Cmd = ["vmq-admin", "listener", "start"],
    KeySpecs = [{port, [{typecast, fun(StrP) ->
                                           case catch list_to_integer(StrP) of
                                               P when (P >= 0) and (P=<65535) -> P;
                                               _ -> {error, {invalid_flag_value,
                                                             {port, StrP}}}
                                           end
                                   end}]}],
    FlagSpecs = [{address, [{shortname, "a"},
                            {longname, "address"},
                            {typecast, fun(A) ->
                                               case inet:parse_address(A) of
                                                   {ok, Ip} -> Ip;
                                                   {error, einval} ->
                                                       {error, {invalid_flag_value,
                                                                {address, A}}}
                                               end
                                       end}]},
                 {mountpoint, [{shortname, "m"},
                               {longname, "mountpoint"},
                               {typecast, fun(MP) -> MP end}]},
                 {max_connections, [{longname, "max-connections"},
                               {typecast, fun(MaxConns) -> MaxConns end}]},
                 {websocket, [{shortname, "ws"},
                              {longname, "websocket"}]},
                 {ssl, [{longname, "ssl"}]},
                 {cafile, [{longname, "cafile"},
                           {typecast, fun(FileName) ->
                                              case filelib:is_file(FileName) of
                                                  true -> FileName;
                                                  false ->
                                                      {error, {invalid_flag_value,
                                                               {cafile, FileName}}}
                                              end
                                      end}]},
                 {certfile, [{longname, "certfile"},
                             {typecast, fun(FileName) ->
                                                case filelib:is_file(FileName) of
                                                    true -> FileName;
                                                    false ->
                                                        {error, {invalid_flag_value,
                                                                 {certfile, FileName}}}
                                                end
                                        end}]},
                 {keyfile, [{longname, "keyfile"},
                            {typecast, fun(FileName) ->
                                               case filelib:is_file(FileName) of
                                                   true -> FileName;
                                                   false ->
                                                       {error, {invalid_flag_value,
                                                                {keyfile, FileName}}}
                                               end
                                       end}]},
                 {ciphers, [{longname, "ciphers"},
                            {typecast, fun(C) -> C end}]},
                 {crlfile, [{longname, "crlfile"},
                            {typecast, fun(FileName) ->
                                               case filelib:is_file(FileName) of
                                                   true -> FileName;
                                                   false ->
                                                       {error, {invalid_flag_value,
                                                                {crlfile, FileName}}}
                                               end
                                       end}]},
                 {require_certificate, [{longname, "require-certificate"}]},
                 {tls_version, [{longname, "tls-version"},
                                {typespec, fun("sslv3") -> sslv3;
                                              ("tlsv1") -> tlsv1;
                                              ("tlsv1.1") -> 'tlsv1.1';
                                              ("tlsv1.2") -> 'tlsv1.2';
                                              (V) ->
                                                   {error, {invalid_flag_value,
                                                            {'tls-version', V}}}
                                           end}]},
                 {use_identity_as_username, [{longname, "use-identity-as-username"}]}
                ],
    Callback =
    fun ([], _) ->
            Text = lists:flatten(vmq_listener_start_usage()),
            [clique_status:alert([clique_status:text(Text)])];
        ([{port, Port}], Flags) ->
            Addr = proplists:get_value(address, Flags, {0,0,0,0}),
            IsWebSocket = lists:keymember(websocket, 1, Flags),
            IsSSL = lists:keymember(ssl, 1, Flags),
            NewOpts1 = lists:keydelete(address, 1, lists:keydelete(port, 1, Flags)),

            case IsSSL of
                true when IsWebSocket ->
                    start_listener(wss, Addr, Port, NewOpts1);
                true ->
                    start_listener(ssl, Addr, Port, NewOpts1);
                false when IsWebSocket ->
                    start_listener(ws, Addr, Port, NewOpts1);
                false ->
                    start_listener(tcp, Addr, Port, NewOpts1)
            end
    end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

start_listener(Type, Addr, Port, Opts) ->
    case vmq_ranch_config:start_listener(Type, Addr, Port, Opts) of
        ok ->
            ListenerKey = {Addr, Port},
            {TCP, SSL, WS, WSS} = vmq_config:get_env(listeners),
            NewListenerConf = {lists:keydelete(ListenerKey, 1, TCP),
                               lists:keydelete(ListenerKey, 1, SSL),
                               lists:keydelete(ListenerKey, 1, WS),
                               lists:keydelete(ListenerKey, 1, WSS)},
            UpdatedConf = update_conf(Type, {ListenerKey, Opts}, NewListenerConf),
            vmq_config:set_env(listeners, UpdatedConf),
            [clique_status:text("Done")];
        {error, Reason} ->
            Text = io_lib:format("can't start listener due to '~p'", [Reason]),
            [clique_status:alert([clique_status:text(Text)])]
    end.

update_conf(tcp, ListenerConf, {TCP,_,_,_} = CleanedConf) ->
    setelement(1, CleanedConf, [ListenerConf|TCP]);
update_conf(ssl, ListenerConf, {_,SSL,_,_} = CleanedConf) ->
    setelement(2, CleanedConf, [ListenerConf|SSL]);
update_conf(ws, ListenerConf, {_,_,WS,_} = CleanedConf) ->
    setelement(3, CleanedConf, [ListenerConf|WS]);
update_conf(wss, ListenerConf, {_,_,_,WSS} = CleanedConf) ->
    setelement(4, CleanedConf, [ListenerConf|WSS]).


vmq_listener_stop_cmd() ->
    Cmd = ["vmq-admin", "listener", "stop"],
    KeySpecs = [],
    FlagSpecs = [{port, [{shortname, "p"},
                         {longname, "port"},
                         {typecast, fun(StrP) ->
                                            case catch list_to_integer(StrP) of
                                                P when (P >= 0) and (P=<65535) -> P;
                                                _ -> {error, {invalid_flag_value,
                                                              {port, StrP}}}
                                            end
                                    end}]},
                 {address, [{shortname, "a"},
                            {longname, "address"},
                            {typecast, fun(A) ->
                                               case inet:parse_address(A) of
                                                   {ok, Ip} -> Ip;
                                                   {error, einval} ->
                                                       {error, {invalid_flag_value,
                                                                {address, A}}}
                                               end
                                       end}]},
                 {kill, [{shortname, "k"},
                         {longname, "kill-sessions"}]}],
    Callback =
    fun([], Flags) ->
            Port = proplists:get_value(port, Flags, 1883),
            Addr = proplists:get_value(address, Flags, {0,0,0,0}),
            IsKill = lists:keymember(kill, 1, Flags),
            case vmq_ranch_config:stop_listener(Addr, Port, IsKill) of
                ok ->
                    [clique_status:text("Done")];
                {error, Reason} ->
                    Text = io_lib:format("can't stop listener due to '~p'", [Reason]),
                    [clique_status:alert([clique_status:text(Text)])]
            end
    end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

vmq_listener_delete_cmd() ->
    Cmd = ["vmq-admin", "listener", "delete"],
    KeySpecs = [],
    FlagSpecs = [{port, [{shortname, "p"},
                         {longname, "port"},
                         {typecast, fun(StrP) ->
                                            case catch list_to_integer(StrP) of
                                                P when (P >= 0) and (P=<65535) -> P;
                                                _ -> {error, {invalid_flag_value,
                                                              {port, StrP}}}
                                            end
                                    end}]},
                 {address, [{shortname, "a"},
                            {longname, "address"},
                            {typecast, fun(A) ->
                                               case inet:parse_address(A) of
                                                   {ok, Ip} -> Ip;
                                                   {error, einval} ->
                                                       {error, {invalid_flag_value,
                                                                {address, A}}}
                                               end
                                       end}]}],
    Callback =
    fun([], Flags) ->
            Port = proplists:get_value(port, Flags, 1883),
            Addr = proplists:get_value(address, Flags, {0,0,0,0}),
            case vmq_ranch_config:delete_listener(Addr, Port) of
                ok ->
                    {TCP, SSL, WS, WSS} = vmq_config:get_env(listeners),
                    ListenerKey = {Addr, Port},
                    ListenerConfig = {lists:keydelete(ListenerKey, 1, TCP),
                                      lists:keydelete(ListenerKey, 1, SSL),
                                      lists:keydelete(ListenerKey, 1, WS),
                                      lists:keydelete(ListenerKey, 1, WSS)},
                    vmq_config:set_env(listeners, ListenerConfig),
                    [clique_status:text("Done")];
                {error, Reason} ->
                    Text = io_lib:format("can't delete listener due to '~p'", [Reason]),
                    [clique_status:alert([clique_status:text(Text)])]
            end
    end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

vmq_listener_restart_cmd() ->
    Cmd = ["vmq-admin", "listener", "restart"],
    KeySpecs = [],
    FlagSpecs = [{port, [{shortname, "p"},
                         {longname, "port"},
                         {typecast, fun(StrP) ->
                                            case catch list_to_integer(StrP) of
                                                P when (P >= 0) and (P=<65535) -> P;
                                                _ -> {error, {invalid_flag_value,
                                                              {port, StrP}}}
                                            end
                                    end}]},
                 {address, [{shortname, "a"},
                            {longname, "address"},
                            {typecast, fun(A) ->
                                               case inet:parse_address(A) of
                                                   {ok, Ip} -> Ip;
                                                   {error, einval} ->
                                                       {error, {invalid_flag_value,
                                                                {address, A}}}
                                               end
                                       end}]}],
    Callback =
    fun([], Flags) ->
            Port = proplists:get_value(port, Flags, 1883),
            Addr = proplists:get_value(address, Flags, {0,0,0,0}),
            case vmq_ranch_config:restart_listener(Addr, Port) of
                ok ->
                    [clique_status:text("Done")];
                {error, Reason} ->
                    Text = io_lib:format("can't restart listener due to '~p'", [Reason]),
                    [clique_status:alert([clique_status:text(Text)])]
            end
    end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

vmq_listener_show_cmd() ->
    Cmd = ["vmq-admin", "listener", "show"],
    KeySpecs = [],
    FlagSpecs = [],
    Callback =
    fun([], []) ->
            Table =
            lists:foldl(
              fun({Type, Ip, Port, Status, MP, MaxConns}, Acc) ->
                      [[{type, Type}, {status, Status}, {ip, Ip},
                        {port, Port}, {mountpoint, MP}, {max_conns, MaxConns}]
                       |Acc]
              end, [], vmq_ranch_config:listeners()),
              [clique_status:table(Table)]
    end,
    clique:register_command(Cmd, KeySpecs, FlagSpecs, Callback).

vmq_listener_usage() ->
    ["vmq-admin listener <sub-command>\n\n",
     "  starts, modifies, and stops listeners.\n\n",
     "  Sub-commands:\n",
     "    start       Starts or modifies a listener\n",
     "    stop        Stops a listener\n",
     "    delete      Deletes a stopped listener\n",
     "    show        Shows all intalled listeners\n",
     "  Use --help after a sub-command for more details.\n"
    ].

vmq_listener_start_usage() ->
    ["vmq-admin listener start port=1883\n\n",
     "  Starts a new listener or modifies an existing listener. If no option\n",
     "  is specified a TCP listener is started listening on the given port\n\n",
     "General Options\n\n",
     "  -a, --address=IpAddress\n",
     "  -m, --mountpoint=Mountpoint\n\n",
     "WebSocket Options\n\n",
     "  --websocket\n",
     "      use the Websocket protocol as the underlying transport\n\n",
     "SSL Options\n\n",
     "  --ssl\n",
     "      use SSL for this listener, without this option, all other SSL\n",
     "      are ignored\n",
     "  --cafile=CaFile\n",
     "      The path to the cafile containing the PEM encoded CA certificates\n" ,
     "      that are trusted by the server.\n",
     "  --certfile=CertificateFile\n",
     "      The path to the PEM encoded server certificate\n",
     "  --keyfile=KeyFile\n",
     "      The path to the PEM encoded key file\n",
     "  --ciphers=CiphersList\n",
     "      The list of allowed ciphers, each separated by a colon\n",
     "  --crlfile=CRLFile\n",
     "      If --require-certificate is set, you can use a certificate\n",
     "      revocation list file to revoke access to particular client\n",
     "      certificates. The file has to be PEM encoded.\n",
     "  --tls-version=TLSVersion\n",
     "      use this TLS version for the listener\n",
     "  --require_certificate\n",
     "      Use client certificates to authenticate your clients\n",
     "  --use-identity-as-username\n",
     "      If --require-certificate is set, the CN value from the client\n",
     "      certificate is used as the username for authentication\n\n"
    ].

vmq_listener_stop_usage() ->
    ["vmq-admin listener stop\n\n",
     "  Stops a running listener. If no option is given, the listener\n",
     "  listening on 0.0.0.0:1883 is stopped\n\n",
     "Options\n\n",
     "  -p, --port=PortNr\n",
     "  -a, --address=IpAddress\n\n"
    ].

vmq_listener_delete_usage() ->
    ["vmq-admin listener delete\n\n",
     "  Deletes a stopped listener. If no option is given, the listener\n",
     "  listening on 0.0.0.0:1883 is deleted\n\n",
     "Options\n\n",
     "  -p, --port=PortNr\n",
     "  -a, --address=IpAddress\n\n"
    ].

vmq_listener_restart_usage() ->
    ["vmq-admin listener restart\n\n",
     "  Restarts a stopped listener. If no option is given, the listener\n",
     "  listening on 0.0.0.0:1883 is restarted\n\n",
     "Options\n\n",
     "  -p, --port=PortNr\n",
     "  -a, --address=IpAddress\n\n"
    ].
