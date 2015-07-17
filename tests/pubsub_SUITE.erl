%%%===================================================================
%%% @copyright (C) 2012, Erlang Solutions Ltd.
%%% @doc Suite for testing pubsub features as described in XEP-0060
%%% @end
%%%===================================================================

-module(pubsub_SUITE).
-compile(export_all).

-include_lib("escalus/include/escalus.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("escalus/include/escalus_xmlns.hrl").
-include_lib("exml/include/exml.hrl").
-include_lib("exml/include/exml_stream.hrl").

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------


%% pubsub_full_cycle
%% case where owner creates a node, publishes to it and gets what he published. It's a round-trip one-user case. 



all() ->
    [{group, pubsub_full_cycle_two_users}].

groups() ->
    [{pubsub_full_cycle_two_users, [sequence], [
				      request_to_create_node_success,
				      request_to_publish_to_node_success, 
				      request_to_subscribe_to_node_success,
				      listen_to_subscribed_node_success,
				      request_to_unsubscribe_from_node_success
				     ]}].

%%    [{pubsub, [sequence], [request_to_create_node]}].
%%    [{pubsub, [sequence], [request_to_create_node, request_to_delete_node_success]}].



suite() ->
    escalus:suite().

%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus:end_per_suite(Config).

init_per_group(_GroupName, Config) ->
    escalus:create_users(Config,{by_name, [alice]}).

end_per_group(_GroupName, Config) ->
    escalus:delete_users(Config,{by_name, [alice]}).

init_per_testcase(listen_to_subscribed_node_success, Config) ->
    Config2 = escalus:create_users(Config,{by_name, [bob]}),
    escalus:init_per_testcase(listen_to_subscribed_node_success, Config2);

init_per_testcase(_TestName, Config) ->
    escalus:init_per_testcase(_TestName, Config).

end_per_testcase(listen_to_subscribed_node_success, Config) ->
    Config2 = escalus:delete_users(Config,{by_name, [bob]}),
    escalus:end_per_testcase(listen_to_subscribed_node_success, Config2);

end_per_testcase(_TestName, Config) ->
    escalus:end_per_testcase(_TestName, Config).





%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------



%% ---------------- PUB SUB STANZAS -------------



pubsub_stanza(Children, NS) ->
    #xmlel{name = <<"pubsub">>,
	     attrs = [{<<"xmlns">>, NS} ],
	     children = Children  }.

create_specific_node_stanza(NodeName) ->
    #xmlel{
       name = <<"create">>,
       attrs = [{<<"node">>, NodeName}] }.

iq_with_id(TypeAtom, Id, To, From, Body) ->
    S1 = escalus_stanza:iq(To, atom_to_binary(TypeAtom, latin1), Body),
    iq_set_get_rest(S1, Id, From).

iq_set_get_rest(SrcIq, Id, From) ->
    S2 = escalus_stanza:set_id(SrcIq, Id),							
    escalus_stanza:from(S2, escalus_utils:get_jid(From)).


sample_publish_item_body() ->
    #xmlel{
       name = <<"entry">>,
       attrs = [{<<"xmlns">>, <<"http://www.w3.org/2005/Atom">>}],
       children = [ #xmlcdata{content=[<<"blabla gugu gaga">>]} ]
      }.

sample_publish_item(Id) ->
    #xmlel{
       name = <<"item">>,
       attrs = [{<<"id">>, Id}],
       children = sample_publish_item_body()
      }.

sample_publish_node_with_content(NodeName) ->
    #xmlel{
       name = <<"publish">>,
       attrs = [{<<"node">>, NodeName}],
       children = sample_publish_item(<<"abc123">>)
      }.
  

create_publish_node_content_stanza(NodeName) ->
    PublNode = sample_publish_node_with_content(NodeName),
    pubsub_stanza([PublNode], ?NS_PUBSUB).

%% ------------ subscribe - unscubscribe -----------


create_subscribe_node_stanza(NodeName, From) ->
    SubsrNode = create_sub_unsubscribe_from_node_stanza(NodeName, From, <<"subscribe">>),
    pubsub_stanza([SubsrNode], ?NS_PUBSUB).


create_unsubscribe_from_node_stanza(NodeName, From) ->
    UnsubsrNode = create_sub_unsubscribe_from_node_stanza(NodeName, From, <<"unsubscribe">>),
    pubsub_stanza([UnsubsrNode], ?NS_PUBSUB).


create_sub_unsubscribe_from_node_stanza(NodeName, From, SubUnsubType) ->
    #xmlel{name = SubUnsubType,
	   attrs = [
		    {<<"node">>, NodeName},
		    {<<"jid">>, escalus_utils:get_jid(From)}]
	  }.

%% ----end----- subscribe - unscubscribe -----------

delete_node_stanza(NodeName) ->
    DelNode = #xmlel{name = <<"delete">>,
		      attrs = [
			       {<<"node">>, NodeName}
			      ]
		      },
    pubsub_stanza([DelNode], ?NS_PUBSUB_OWNER).


%% ---END---------- PUB SUB STANZAS -------------

-define (DEST_NODE_ADDR, <<"pubsub.localhost">>).
-define (DEFAULT_TOPIC_NAME, <<"princely_musings">>).
   
%% XEP0060---8.1.1 Create a node with default configuration ---------------------------
request_to_create_node_success(Config) ->
    escalus:story(Config, [1],
		   fun(Alice) ->
			   PubSubCreate = create_specific_node_stanza(?DEFAULT_TOPIC_NAME),
			   PubSub = pubsub_stanza([PubSubCreate], ?NS_PUBSUB),
			   DestinationNode = ?DEST_NODE_ADDR,
			   Id = <<"create1">>,
			   PubSubCreateIq  =  iq_with_id(set, Id, DestinationNode, Alice,  [PubSub]),
			   ct:pal(" Request PubSubCreateIq: ~n~n~p~n",[exml:to_binary(PubSubCreateIq)]),
			   escalus:send(Alice, PubSubCreateIq),
			   {true, _RecvdStanza} = wait_for_stanza_and_match_iq(Alice, Id, DestinationNode)
			   %% example 131
		   end).

%% XEP0060---7.1.1 Request to publish to a node -----------------------------------------
request_to_publish_to_node_success(Config) ->
     escalus:story(Config, [1],
		   fun(Alice) ->
			   PublishToNode = create_publish_node_content_stanza(?DEFAULT_TOPIC_NAME),
			   DestinationNode = ?DEST_NODE_ADDR,
			   Id = <<"publish1">>,
			   PublishToNodeIq  =  iq_with_id(set, Id, DestinationNode, Alice,  [PublishToNode]),
			   ct:pal(" Request PublishToNodeIq: ~n~n~p~n",[exml:to_binary(PublishToNodeIq)]),
			   escalus:send(Alice, PublishToNodeIq),
			   {true, _RecvdStanza} = wait_for_stanza_and_match_iq(Alice, Id, DestinationNode)
			   %% see example 100
		   end).

    
%% XEP0060---6.1.1 Subscribe to node request --------------------------------------------
%% Note: it is the OWNER and PUBLISHER Alice who is subscribing...
request_to_subscribe_to_node_success(Config) ->
     escalus:story(Config, [1],
		   fun(Alice) ->
			   SubscribeToNode = create_subscribe_node_stanza(?DEFAULT_TOPIC_NAME, Alice),
			   DestinationNode = ?DEST_NODE_ADDR,
			   Id = <<"sub1">>,
			   SubscribeToNodeIq  =  iq_with_id(set, Id, DestinationNode, Alice,  [SubscribeToNode]),
			   ct:pal(" Request SubscribeToNodeIq: ~n~n~p~n",[exml:to_binary(SubscribeToNodeIq)]),
			   escalus:send(Alice, SubscribeToNodeIq),
			   {true, RecvdStanza} = wait_for_stanza_and_match_iq(Alice, Id, DestinationNode),
			   is_subscription_for_jid_pred(RecvdStanza, Alice)
			   %% see example 33
		   end).

%% XEP0060---7.1.2 Consume notification including payload-------------------------------------
%% Bob is subscribing and waits for notification since Alice has already published
listen_to_subscribed_node_success(Config) ->
     escalus:story(Config, [{bob,1}],
		   fun(Bob) ->
			   SubscribeToNode = create_subscribe_node_stanza(?DEFAULT_TOPIC_NAME, Bob),
			   DestinationNode = ?DEST_NODE_ADDR,
			   Id = <<"bobsub1">>,
			   SubscribeToNodeIq  =  iq_with_id(set, Id, DestinationNode, Bob,  [SubscribeToNode]),
			   ct:pal(" Request SubscribeToNodeIq from Bob: ~n~n~p~n",[exml:to_binary(SubscribeToNodeIq)]),
			   escalus:send(Bob, SubscribeToNodeIq),
			   %% First - confirm subscription
			   {true, Res1} = wait_for_stanza_and_match_iq(Bob, Id, DestinationNode), %%wait for subscr. confirmation
			   %% Second - wait for notification with payload (alice already published)
			   ResultNotificationStanza = escalus:wait_for_stanza(Bob), %%and wait for the notification
			   ct:pal(" --- got from server ---- : ~n~n~p~n", [exml:to_binary(ResultNotificationStanza)]),
			   Res1
			   
			   %% see example 101    
		   end).

    

%% XEP0060---6.2.1 Unubscribe from node request --------------------------------------------
request_to_unsubscribe_from_node_success(Config) ->

     escalus:story(Config, [1],
		   fun(Alice) ->
			   UnubscribeFromNode = create_unsubscribe_from_node_stanza(?DEFAULT_TOPIC_NAME, Alice),
			   DestinationNode = ?DEST_NODE_ADDR,
			   Id = <<"unsub1">>,
			   UnSubscribeFromNodeIq  =  iq_with_id(set, Id, DestinationNode, Alice,  [UnubscribeFromNode]),
			   ct:pal(" Request UnSubscribeFromNodeIq: ~n~n~p~n",[exml:to_binary(UnSubscribeFromNodeIq)]),
			   escalus:send(Alice, UnSubscribeFromNodeIq),
			   {true, _RecvdStanza} = wait_for_stanza_and_match_iq(Alice, Id, DestinationNode)
		   end).



%% XEP0060---8.4.1 Delete node request --------------------------------------------
request_to_delete_node_success(Config) ->

     escalus:story(Config, [1], 
		   fun(Alice) ->
			   DeleteNode = delete_node_stanza(?DEFAULT_TOPIC_NAME),
			   DestinationNode = ?DEST_NODE_ADDR,
			   Id = <<"delete1">>,
			   DeleteNodeIq  =  iq_with_id(set, Id, DestinationNode, Alice,  [DeleteNode]),
			   ct:pal(" Request DeleteNodeIq: ~n~n~p~n",[exml:to_binary(DeleteNodeIq)]),
			   escalus:send(Alice, DeleteNodeIq),
			   {true, _RecvdStanza} = wait_for_stanza_and_match_iq(Alice, Id, DestinationNode)
		   end).


%% ----------------------------- HELPER and DIAGNOSTIC functions -----------------------

%% Checks superficialy is IQ from server  matches the sent id, there is "result" and sender is correct.
wait_for_stanza_and_match_iq(User, Id, DestinationNode) ->
    ResultStanza = escalus:wait_for_stanza(User),
    ct:pal(" Response stanza from server: ~n~n~s~n", [exml:to_binary(ResultStanza)]),

    QueryStanza = escalus_stanza:iq_with_type_id_from(<<"result">>, Id, DestinationNode),
    %%  ct:pal("QueryStanza: ~s~n",[exml:to_binary(QueryStanza)]),

    Result = escalus_pred:is_iq_result(QueryStanza, ResultStanza),
    %%  ct:pal(" result - ~s~n", [exml:to_binary(Result)]),

    {Result, ResultStanza}.

%% generate dummy subscription confirmation from server. Used to test predicate function.
get_subscription_confirmation_stanza() ->
   Subscription = #xmlel{name = <<"subscription">>, attrs=[{<<"jid">>, <<"alice@localhost">>}]},
   PubSub = pubsub_stanza([Subscription], ?NS_PUBSUB),
   DestinationNode = ?DEST_NODE_ADDR,
   Id = <<"sub1">>,
   PubSubItemIq  =  iq_with_id(set, Id, DestinationNode, <<"Alice">>,  [PubSub]),
   %%io:format(" ---- ~n~p~n ", [PubSubItemIq]),
   %%B = exml:to_binary(PubSubItemIq),
   %%io:format(" ---- ~n~p~n ", [B]),
   PubSubItemIq.
	
is_subscription_for_jid_pred(SubscrConfirmation, User) ->
    %% Stanza = get_subscription_confirmation_stanza(),
    %% R = exml_query:path(Stanza, <<"pubsub>>">>),
    R1 = exml_query:subelement(SubscrConfirmation, <<"pubsub">>),
    io:format(" -- ~n~p",[R1]),
    R2 = exml_query:subelement(R1, <<"subscription">>),
    io:format(" ------ ~n~p",[R2]),
    JidOfSubscr = exml_query:attr(R2, <<"jid">>),
    io:format(" -- jid found : ~n~p", [JidOfSubscr]),
    escalus:assert(JidOfSubscr,  escalus_utils:get_jid(User)).

















