-module(mod_simple_archive).
-behavior(gen_mod).
-include("jlib.hrl").
-include("ejabberd.hrl").
-export([start/2, stop/1]).
-export([on_user_send_packet/3]).

-define(INFINITY, calendar:datetime_to_gregorian_seconds({{2038,1,19},{0,0,0}})).

start(Host, _Opts) ->
    ?INFO_MSG("mod_simple_archive starting", []),
    ejabberd_hooks:add(user_send_packet, Host, ?MODULE, on_user_send_packet, 0),
    ok.

stop(Host) ->
    ?INFO_MSG("mod_simple_archive stopping", []),
    ejabberd_hooks:delete(user_send_packet, Host, ?MODULE, on_user_send_packet, 0),
    ok.

escape_chars($')  -> "''";
escape_chars(C)  -> C.

escape_str(Str) ->
  "'" ++ ejabberd_odbc:escape(Str) ++ "'".

escape(null) ->
    "null";
escape(undefined) ->
    "null";
escape(infinity) ->
    integer_to_list(?INFINITY);
escape(Num) when is_integer(Num) ->
    integer_to_list(Num);
escape(Str) ->
    "'" ++ [escape_chars(C) || C <- Str] ++ "'".

get_timestamp() ->
    calendar:datetime_to_gregorian_seconds(calendar:universal_time()).

encode_timestamp(infinity) ->
    escape(get_sql_datetime_string_from_seconds(?INFINITY));

encode_timestamp(TS) ->
    escape(get_sql_datetime_string_from_seconds(TS)).

get_sql_datetime_string_from_seconds(Secs) ->
    Zero = calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}),
    Secs2 = Secs - Zero,
    now_to_utc_sql_datetime({Secs2 div 1000000, Secs2 rem 1000000, 0}).

now_to_utc_sql_datetime({MegaSecs, Secs, MicroSecs}) ->
    {{Year, Month, Day}, {Hour, Minute, Second}} =
  calendar:now_to_universal_time({MegaSecs, Secs, MicroSecs}),
    lists:flatten(
      io_lib:format("~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w",
        [Year, Month, Day, Hour, Minute, Second])).

run_sql_transaction(LServer, F) ->
    DBHost = gen_mod:get_module_opt(LServer, ?MODULE, db_host, LServer),
    case ejabberd_odbc:sql_transaction(DBHost, F) of
        {atomic, R} ->
	    %%?MYDEBUG("succeeded transaction: ~p", [R]),
	    R;
        {error, Err} -> {error, Err};
        E ->
            ?ERROR_MSG("failed transaction: ~p, stack: ~p", [E, process_info(self(),backtrace)]),
            {error, ?ERR_INTERNAL_SERVER_ERROR}
    end.


run_sql_query(Query) ->
    %%?MYDEBUG("running query: ~p", [lists:flatten(Query)]),
    case catch ejabberd_odbc:sql_query_t(Query) of
        {'EXIT', Err} ->
            ?ERROR_MSG("unhandled exception during query: ~p", [Err]),
            exit(Err);
        {error, Err} ->
            ?ERROR_MSG("error during query: ~p", [Err]),
            throw({error, Err});
        aborted ->
            ?ERROR_MSG("query aborted", []),
            throw(aborted);
        R -> %?MYDEBUG("query result: ~p", [R]),
      R
    end.

on_user_send_packet(From, To, Packet) ->
    Type = xml:get_tag_attr_s("type", Packet),
    Body = xml:get_path_s(Packet, [{elem, "body"}, cdata]),
    LServer = From#jid.lserver,

    if
      (Type == "chat") and (Body /= "") ->
        F = fun() ->
          run_sql_query(["insert into sh_messages (from_jid, to_jid, body, utc) "
                       "values (", escape_str(From#jid.luser), ", ",
                       escape_str(To#jid.luser), ", ",
                       escape_str(Body), ", ",
                       encode_timestamp(get_timestamp()),
                       ")"])
        end,
        run_sql_transaction(LServer, F),
        ok;
      true ->
        ok
    end.
