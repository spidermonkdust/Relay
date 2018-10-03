
/* -*- Mode: vala; indent-tabs-mode: t; c-basic-offset: 4; tab-width: 4 -*-  */
/*
 * connection.vala
 * Copyright (C) 2015 Kyle Agronick <stack@kyle-ele>
	 *
 * KyRC is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
	 *
 * KyRC is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using GLib;
using Gtk;
using Gee;

public class Connection : Object
{

	public const uint16 DEFAULT_PORT = 6667;
	private DataInputStream input_stream;
	private DataOutputStream output_stream;
	public ChannelTab server_tab;
	public HashMap<string, ChannelTab> channel_tabs = new HashMap<string, ChannelTab>();
	public LinkedList<string> channel_autoconnect = new LinkedList<string>();
	public bool exit = false;
	public bool error_state = false;
	public bool autoconnect_ran = false;
	public SqlClient.Server server;

	public signal void new_tab(ChannelTab tab, string name);
	public signal void new_message(ChannelTab? tab, Message message, bool is_error = false);
	public signal void change_channel_state(string chan_name, string state);

	public bool connect_to_server (SqlClient.Server _server) {
		server = _server;
		server_tab = add_channel_tab(server.host);
		server_tab.is_server_tab = true; 

		new Thread<int>("Connection " + server.host, do_connect);

		return true;
	}

	private int do_connect () {
		try{
			Resolver resolver = Resolver.get_default ();
			GLib.List<InetAddress> addresses = resolver.lookup_by_name(server.host, null);
			InetAddress address = addresses.nth_data (0);

 
			SocketClient client = new SocketClient ();
			client.set_tls(server.encryption);
			client.set_tls_validation_flags(TlsCertificateFlags.UNKNOWN_CA);
			// Resolve hostname to IP address:
			SocketConnection conn = client.connect (new InetSocketAddress (address, (uint16) server.port));
			input_stream = new DataInputStream (conn.input_stream);
			output_stream = new DataOutputStream (conn.output_stream);

			if (server.username.strip().length == 0) 
				server.username = Environment.get_user_name();
			if (server.nickname.strip().length == 0)
				server.nickname = Environment.get_user_name();
			if (server.realname.strip().length == 0)
				server.realname = server.nickname;
				
			do_register();

			string? line = "";
			do{
				size_t size;
				try{
					line = input_stream.read_line(out size);
					debug("Raw input " + line);
					handle_input(line);
				}catch(IOError e) {
					error_state = true;
					warning("IO error while reading " + e.message);
				}
			}while (line != null && !exit);
		} catch (GLib.Error err) {
			var e = (owned) err;
			warning("Could not connect " + e.message);
			error_state = true;
			Idle.add( ()=> {
				Relay.show_error_window(e.message);
				server_tab.tab.close();
				foreach (string tab in channel_autoconnect)
					turn_off_icon(tab);
				return false;
			});
			return 0;
		}

		return 1;
	}

	public ChannelTab? add_channel_tab (string? _name, bool primsg = false) {
		string? name = _name;
		if (name == null || name.strip() == "" || server == null)
			return null;
		if (name == server.username || (name == server.nickname && !primsg) || name == "IRC")
			return server_tab;
		if (channel_tabs.has_key(name))
			return channel_tabs[name];
		var newTab = new ChannelTab(this);
		new_tab(newTab, name); 
		channel_tabs[name] = newTab;
		return newTab;
	}

	//Same as add_channel_tab but won't create if not found
	private ChannelTab? find_channel_tab (string? name) {
		if (name == null)
			return null;
		else if (channel_tabs.has_key(name))
			return channel_tabs[name];

		return server_tab;
	}

	private void handle_input (string? msg) {
		if (msg == null) {
			stop();
			return;
		}  

		Message message = new Message (msg);
		switch (message.command) {
			case "PING":
				handle_ping(ref message);
				return;
			case "PONG":
				info(msg);
				return;
			case IRC.PRIVATE_MESSAGE: 
				ChannelTab tab = add_channel_tab(message.parameters[0]);
				if (tab == server_tab && message.parameters[0] == server.nickname) {
					tab = add_channel_tab(message.user_name, true);
				}
				if (tab != null)
					new_message(tab, message);
				return;
			case IRC.RPL_TOPIC:
				ChannelTab tab = find_channel_tab(message.parameters[1]);
				if (tab != null && tab != server_tab)
					tab.set_topic(message.get_msg_txt());
				return;
			case IRC.RPL_CHANNEL_URL:
				ChannelTab tab = find_channel_tab(message.parameters[1]);
				if (tab != null && tab != server_tab)
					tab.channel_url =  message.message;
				return;
			case IRC.RPL_LUSERCLIENT:
			case "NOTICE":
			case IRC.RPL_MOTD:
			case IRC.RPL_MOTDSTART:
			case IRC.RPL_YOURHOST:
			case IRC.RPL_LUSEROP:
			case IRC.RPL_LUSERUNKNOWN:
			case IRC.RPL_LUSERCHANNELS:
			case IRC.RPL_UMODEIS: //maybe atab
			case IRC.RPL_SERVLIST:
			case IRC.RPL_ENDOFSTATS:
			case IRC.RPL_STATSLINKINFO:
				server_tab.display_message(message);
				return;
			case IRC.RPL_CREATED:
			case IRC.RPL_LUSERME:
				server_tab.set_topic(message.get_msg_txt(), true);
				new_message(server_tab, message);
				return;
			case IRC.RPL_WELCOME:
				do_autoconnect();
				run_on_connect_cmds();
				if (channel_autoconnect.size == 0)
					server_tab.tab.working = false;
				break;
			case IRC.RPL_NAMREPLY:
				var tab = add_channel_tab(message.parameters[2]);
				if (tab == null || tab == server_tab)
					return;
				tab.add_users_message(message);
				break;
			case IRC.QUIT_MSG:
			case IRC.PART_MSG:
				foreach(var t in channel_tabs.entries) {
					if (!t.value.is_server_tab && t != null && message.user_name != null && message.user_name.length > 0)
						t.value.user_leave_channel(message.user_name, message.get_msg_txt());
				}
				return;
			case IRC.USER_NAME_CHANGED:
				foreach(var t in channel_tabs.entries) {
					if (t != null && message.user_name != null && message.user_name.length > 0)
						t.value.user_name_change(message.user_name, message.get_msg_txt());
				}
				return;
			case IRC.JOIN_MSG:
				var tab = find_channel_tab(message.get_msg_txt());
				if (tab == server_tab)
					tab = find_channel_tab(message.parameters[0]);
				if (tab != server_tab && tab != null && message.user_name != null && message.user_name.length > 0)
					tab.user_join_channel(message.user_name);
				return;
			case IRC.RPL_ENDOFNAMES:
				var tab = find_channel_tab(message.parameters[1]);
				if (tab != null)
					tab.sort_names();
				return;
				//Errors
			case IRC.ERR_NICKNAMEINUSE:
			case IRC.ERR_NONICKNAMEGIVEN:
				string error_msg = message.get_msg_txt();
				if (message.get_msg_txt().length < 3)
					error_msg = _("The name you chose is in use.");
				error_msg = server.host + "\n" + error_msg;
				name_in_use(error_msg);
				return;
			case IRC.ERR_LINKCHANNEL:
				//Channel forwarding
				if (message.parameters.length < 2)
					return;
				turn_off_icon(message.parameters[1]);
				return;
			case IRC.ERR_NOSUCHNICK:
			case IRC.ERR_NOSUCHCHANNEL:
			case IRC.ERR_WASNOSUCHNICK:
			case IRC.ERR_UNKNOWNCOMMAND:
			case IRC.ERR_NOMOTD:
			case IRC.ERR_USERNOTINCHANNEL:
			case IRC.ERR_NOTONCHANNEL:
			case IRC.ERR_NOTREGISTERED:
			case IRC.ERR_NEEDMOREPARAMS:
			case IRC.ERR_UNKNOWNMODE:
			case IRC.ERR_ALREADYONCHANNEL:
			case IRC.ERR_CHANOPRIVSNEEDED:
			case IRC.ERR_NONONREG:
				new_message(find_channel_tab(message.parameters[0]), message, true);
				return;
			default:
				if (message.command == null)
					message.command = "0";
				else {
					int mode = int.parse(message.command);
					if (message.command == "ERROR" || 
					    (mode <= 533 && mode >= 400) || 
						(mode >= 712 && mode <= 715) || 
						(mode >= 972)) {
						new_message(server_tab, message, true);
						return;
					}
				}
				debug("Unhandled message: " + msg);
				return;
		} 
	}

	public void do_register () {
		send_output("PASS  " + ((server.password.length > 0) ? server.password : "-p"));
		send_output("NICK " + server.nickname);
		send_output("USER " + server.username + " 0 * :" + server.realname);
		send_output("MODE " + server.username + " +i");
	}

	public void do_autoconnect () {
		autoconnect_ran = true;
		foreach (var chan in channel_autoconnect) {
			join(chan);
		}
		Gdk.threads_add_timeout_seconds(25, ()=> {
			foreach (var chan in channel_autoconnect) {
					change_channel_state(chan, "stuck");
			}
			return false;
		});
	}

	public void turn_off_icon (string channel) {
		change_channel_state(channel, "inactive");
	}

	public void run_on_connect_cmds() {
		if (server.connect_cmds != null && server.connect_cmds.length > 0) {
			string[] cmds = server.connect_cmds.split("\n");
			foreach(string run in cmds) {
				if (run.length > 1)
					server_tab.send_text_out(run);
			}
		}
	}

	public void name_in_use (string message) {
		debug("At name in use");
		Idle.add( ()=> {
			var dialog = new Dialog.with_buttons(_("Nickname in use"), MainWindow.window,
			                                     DialogFlags.DESTROY_WITH_PARENT,
			                                     _("Connect"), Gtk.ResponseType.ACCEPT,
			                                     _("Cancel"), Gtk.ResponseType.CANCEL);
			Gtk.Box content = dialog.get_content_area() as Gtk.Box;
			content.pack_start(new Label(_(message)), false, false, 5);
			var server_name = new Entry();
			server_name.placeholder_text = _("New username");
			server_name.activate.connect(() => {
				dialog.response(Gtk.ResponseType.ACCEPT);
			});
			content.pack_start(server_name, false, false, 5);
			dialog.show_all();
			dialog.response.connect((id) => {
				switch (id){
					case Gtk.ResponseType.ACCEPT:
						string name = server_name.get_text().strip();
						if (name.length > 0) {
							server.nickname = server.username = server_name.get_text();
							if (server.realname.length == 0)
								server.realname = server.nickname;
							do_register();
							dialog.close();
						}
						break;
					case Gtk.ResponseType.CANCEL:
						dialog.close();
						server_tab.tab.close();
						foreach (var tab in channel_tabs.entries) {
							tab.value.tab.close();
						}
						break;
				}
			});
			return false;
		});
	}
	
	private void handle_ping (ref Message msg) {
		send_output("PONG " + msg.message);
	}

	public void join (string channel) {
		send_output("JOIN " + channel);
	}

	public void send_output (string output) {
		if (!is_stream_out(output_stream))
			return;
		debug("Sending out " + output + "  " + server.host + "\n");
		try{
			output_stream.put_string(output + "\r\n");
		}catch(GLib.Error e){
			Relay.show_error_window(e.message);
		}
	}

	public bool is_stream_out (DataOutputStream? output) {
		return !(!(output is DataOutputStream) || output == null || output.is_closed());
	}

	public bool is_stream_in (DataInputStream? input) {
		return !(!(input is DataInputStream) || input == null || input.is_closed());
	}

	public void do_exit () {
		exit = true;

		foreach (string chan in channel_autoconnect)
			turn_off_icon(chan);
		
		send_output("QUIT :" + _("Relay, an IRC client for the modern desktop"));
		stop();
	}

	public void stop () {
		exit = true;

		if (is_stream_in (input_stream)) {
			input_stream.clear_pending();
			try{
				input_stream.close();
			} catch (GLib.IOError e){}
		}
		if (is_stream_out(output_stream)) {
			try{
				output_stream.clear_pending();
				output_stream.flush();
				output_stream.close();
			} catch (GLib.Error e){}
		}
		debug("Sucessfully stopped");
	}
}
