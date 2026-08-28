extends GdUnitTestSuite


func test_format_user_line_basic():
	assert_that(AgentPanel.format_user_line("hello")).is_equal("[b]You[/b] hello")


func test_format_user_line_escapes_bracket():
	assert_that(AgentPanel.format_user_line("set_display_param[0]")).is_equal("[b]You[/b] set_display_param[lb]0]")


func test_format_agent_line_basic():
	assert_that(AgentPanel.format_agent_line("hi there")).is_equal("[b]Agent[/b] hi there")


func test_format_agent_line_escapes_bracket():
	assert_that(AgentPanel.format_agent_line("[bold] not real")).is_equal("[b]Agent[/b] [lb]bold] not real")


func test_format_peer_line_basic():
	assert_that(AgentPanel.format_peer_line("hello", 3)).is_equal("[b]Peer 3[/b] hello")


func test_format_peer_line_escapes_bracket():
	assert_that(AgentPanel.format_peer_line("set_display_param[0]", 7)).is_equal("[b]Peer 7[/b] set_display_param[lb]0]")
