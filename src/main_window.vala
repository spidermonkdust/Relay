
/*
 * main_window.vala
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
using Gdk;
using Gee;
using Granite;
using Pango;
using Unity;

public class MainWindow : Object {
    //const string UI_FILE = Config.PACKAGE_DATA_DIR + "/ui/" + "relay.ui";
    public const string UI_FILE = "ui/relay.ui";
    public const string UI_FILE_SERVERS = "ui/server_window.ui";
    public const string UI_FILE_SETTINGS = "ui/settings_window.ui";


    Relay app;
    public static Gtk.Window window;
    public static Entry input;
    public static Icon inactive_channel;
    public static Icon active_channel;
    public static Icon loading_channel;
    public static Icon channel_tab_icon_new_msg;
    public static bool network_state = true;
    Paned panel;
    Gtk.Menu tab_rightclick = new Gtk.Menu();
    Gtk.Menu tab_channel_list = new Gtk.Menu();
    DragFile drag_file = new DragFile();
    Button channel_users = new Button();
    Label subject_text = new Label("");
    Button channel_subject = new Button();
    HeaderBar toolbar = new HeaderBar ();

    //User popover
    Popover users_popover;
    Label users_header = new Label("");
    Box users_list = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
    ScrolledWindow users_scrolled = new Gtk.ScrolledWindow (null, null);
    Gtk.Menu user_menu = new Gtk.Menu();
    string channel_user_selected = "";
    SearchEntry users_search = new SearchEntry();
    
    Granite.Widgets.DynamicNotebook tabs = new Granite.Widgets.DynamicNotebook();
    public static HashMap<string, Widgets.SourceList.Item> items_sidebar = new HashMap<string, Widgets.SourceList.Item>();
    public static Button paste = new Button();
    public static Box paste_box = new Box(Gtk.Orientation.HORIZONTAL, 0);
    public static SqlClient sql_client = SqlClient.get_instance();
    public static Settings settings = new Settings();
    public static ServerManager server_manager = new ServerManager();
    public static Unity.LauncherEntry launcher = Unity.LauncherEntry.get_for_desktop_id(Config.PACKAGE_NAME + ".desktop");

    Gee.HashMap<int, ChannelTab> outputs = new Gee.HashMap<int, ChannelTab> ();
    Gee.HashMap<string, Connection> clients = new Gee.HashMap<string, Connection> (); 
    Granite.Widgets.SourceList servers = new Granite.Widgets.SourceList();

    public static int current_tab = -1;

    public MainWindow (Relay application) {
        try {
            app = application;

            inactive_channel = new Pixbuf.from_file(Relay.get_asset_file("assets/user-offline.svg"));
            active_channel = new Pixbuf.from_file(Relay.get_asset_file("assets/user-idle.svg"));
            loading_channel = new Pixbuf.from_file(Relay.get_asset_file("assets/channel-loading.svg"));

            var builder = new Builder ();
            builder.add_from_file (Relay.get_asset_file(UI_FILE));
            builder.connect_signals(this);

            if (Relay.on_kde)
                toolbar.decoration_layout = "";
            else if (Relay.on_ubuntu)
                toolbar.decoration_layout = "close,maximize";
            
            tabs.add_button_tooltip = _("Connect to a server");
            tabs.add_button_visible = false;
            tabs.allow_drag = true;
            tabs.show_icons = true;
            tabs.show_tabs = settings.get_bool("show_tabs");
            tabs.new_tab_requested.connect(new_tab_requested);

            window = builder.get_object ("window") as Gtk.Window;
            window.set_position(WindowPosition.CENTER);
            Relay.set_color_mode(window.get_style_context().get_color(StateFlags.NORMAL));
            settings.set_colors_defaults();
    
            window.destroy.connect(relay_close_program);
            application.add_window(window);
            var nb_wrapper = builder.get_object("notebook_wrapper") as Box;
            nb_wrapper.pack_start(tabs, true, true, 0); 
            tabs.show_all();
            channel_tab_icon_new_msg = new Pixbuf.from_file(Relay.get_asset_file("assets/mail-unread.svg"));

            //Slide out panel
            panel = builder.get_object("panel") as Paned;
            var server_list_container = builder.get_object("server_list_container") as Box;
            server_list_container.pack_start(servers, true, true, 0);

            //Slide out panel button
            Image icon = new Image.from_file(Relay.get_asset_file("assets/server-icon" + (Relay.is_light_theme ? "-light" : "") + ".svg"));
            Button select_channel = new Gtk.Button();
            select_channel.image = icon;

            select_channel.tooltip_text = _("Open server/channel view");
            toolbar.pack_start(select_channel);
            select_channel.button_release_event.connect(slide_panel);
            panel.position = 1;
            
            var pref_menuitem = new Gtk.MenuItem.with_label (_("Preferences"));
            pref_menuitem.activate.connect (editPreferencesClick);
            
            var pref_menu = new Gtk.Menu ();
            pref_menu.append (pref_menuitem);
            pref_menu.show_all ();
            
            var pref_menu_button = new Gtk.MenuButton ();
            pref_menu_button.image = new Gtk.Image.from_icon_name ("open-menu", Gtk.IconSize.LARGE_TOOLBAR);
            pref_menu_button.popup = pref_menu;
            pref_menu_button.valign = Gtk.Align.CENTER;
            
            toolbar.pack_end (pref_menu_button);
            settings.changed_color.connect(tags_refresh);
            settings.show_hide_tabs.connect( (state)=> {
                tabs.show_tabs = state;
            });

            Box entry_wrapper = builder.get_object("entry_wrapper") as Box;
            input = new MainEntry();
            entry_wrapper.pack_start(input, true, true, 0);
            input.activate.connect (() => {
                send_text_out(input.get_text ());
                input.set_text("");
            });

            //Channel subject button
            channel_subject.image = new Image.from_file(Relay.get_asset_file("assets/help-info-symbolic.svg"));
            channel_subject.tooltip_text = _("Channel subject");
            var subject_popover = new Gtk.Popover(channel_subject);
            channel_subject.clicked.connect(() => {
                subject_popover.show_all();
            });
            channel_subject.set_no_show_all(true);
            channel_subject.hide();
            var scrolled = new ScrolledWindow(null, null);
            subject_text.set_line_wrap(true);
            subject_text.margin = 10;
            scrolled.set_size_request(320, 110);
            scrolled.add(subject_text);
            subject_popover.add(scrolled);
            toolbar.pack_end(channel_subject);

            //Channel users button
            channel_users.image = new Image.from_file(Relay.get_asset_file("assets/system-users.svg"));
            channel_users.tooltip_text = _("Channel users");
            channel_users.hide();
            users_popover = new Gtk.Popover(channel_users);
            channel_users.clicked.connect(() => {
                    users_search.set_text("");
                    make_user_popover("", true);
            });
            users_popover.focus_out_event.connect((event)=> {
                users_popover.closed();
                users_search.set_text("");
                return true;
            });
            toolbar.button_press_event.connect( ()=> {
                toolbar.grab_focus();
                return true;
            });

            users_scrolled.vscrollbar_policy = PolicyType.NEVER;
            users_scrolled.hscrollbar_policy = PolicyType.AUTOMATIC;
            users_scrolled.add(users_list);

            var users_wrap = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var font = new FontDescription();
            font.set_weight(Pango.Weight.BOLD);
            users_search.search_changed.connect( ()=> {
                make_user_popover(users_search.get_text());
            });
            users_header.override_font(font);
            users_header.height_request = 24;
            users_wrap.pack_start(users_header, true, false, 4);
            users_wrap.pack_start(users_search, true, false , 4);
            users_wrap.pack_start(users_scrolled);
            users_popover.add(users_wrap);
            toolbar.pack_end(channel_users);
            Gtk.MenuItem private_message = new Gtk.MenuItem.with_label (_("Private Message"));
            user_menu.add(private_message);
            Gtk.MenuItem block = new Gtk.MenuItem.with_label (_("Block"));
            private_message.button_release_event.connect(click_private_message);
            block.button_release_event.connect(click_block);
            user_menu.add(block);
            user_menu.show_all();

            servers.item_selected.connect(set_item_selected);

            set_up_add_sever(builder);

            toolbar.set_title(app.program_name);

            if (!Relay.on_kde)
                toolbar.show_close_button = true;
            window.set_titlebar(toolbar);
            window.show_all();

            /*
             * Hastebin code
             */ 
            paste_box.pack_start(paste);
            paste_box.show_all();
            paste.focus_on_click = false;
            var paste_img = new Image.from_file(Relay.get_asset_file("./assets/paste.png"));
            paste.set_image(paste_img);
            paste.set_tooltip_text(_("Drag a files here to upload to Hastebin.com"));
            paste.activate();
            toolbar.pack_end(paste_box);
            drag_file.attach_spinner(paste_box);
            drag_file.attach_button(paste);
            Gtk.drag_dest_set(paste, 
                Gtk.DestDefaults.ALL,
                DragFile.TARGETS, 
                Gdk.DragAction.LINK);
            drag_file.file_uploaded.connect(file_uploaded);
            paste.drag_data_received.connect(drag_file.drop_file);

            tabs.tab_removed.connect(tab_remove);
            tabs.tab_switched.connect(tab_switch); 

            refresh_server_list(); 

            load_autoconnect();

            Gtk.MenuItem close_all = new Gtk.MenuItem.with_label(_("Close All"));
            close_all.activate.connect( ()=> {
                foreach(var item in outputs) {
                    if(item != null && item.tab != null) 
                        tabs.remove_tab(item.tab);
                }
            });
            Gtk.MenuItem new_tab = new Gtk.MenuItem.with_label(_("New Tab"));
            new_tab.activate.connect(new_tab_requested);

            Gtk.MenuItem channel_list_menu = new Gtk.MenuItem.with_label(_("Switch"));
            channel_list_menu.set_submenu(tab_channel_list);

            tab_rightclick.add(channel_list_menu);
            tab_rightclick.add(close_all);
            tab_rightclick.add(new_tab);

            tab_rightclick.show_all();


            server_manager.close.connect( () => {
                refresh_server_list ();
            });
            
            if (settings.get_bool("show_sidebar")) {
                slide_panel();
            }
        }
        catch (Error e) {
            error("Could not load UI: %s\n", e.message);
        }

        var network_monitor = NetworkMonitor.get_default();
        network_monitor.network_changed.connect( (on)=> {
            if (!on) {
                if (!network_state)
                    return;
                network_state = false;
                outputs.foreach( (output)=> {
                    var msg = new Message();
                    msg.message = _("You have lost network connectivity.");
                    add_text(output.value, msg, true);
                    return true;
                });
            } else
                network_state = true;
        });
    }

    public void rebuild_channel_list_menu() {
        tab_channel_list.forall( (widget) => {
            tab_channel_list.remove(widget);
        });
        foreach (var tab in outputs.entries) {
            Gtk.MenuItem item = new Gtk.MenuItem.with_label(tab.value.tab.label);
            item.activate.connect( ()=> {
                tabs.current = tab.value.tab;
            });
            tab_channel_list.add(item);
            item.show_all();
        }
        tab_channel_list.show_all();
    }

    public Gtk.Popover make_popover (Button parent) {
        var popover = new Gtk.Popover(parent);
        popover.set_no_show_all(true);
        popover.hide();
        return popover;
    }

    private static Widgets.SourceList.Item current_selected_item;
    private void set_item_selected (Widgets.SourceList.Item? item) {
        current_selected_item = item;
        sidebar_item_activated();
    }

    /* 
     *  The connection calls this method to create a tab anytime a
     *  channel or server is opened
     */
    public static int index = 0;
    public void add_tab (ChannelTab new_tab, string name) {
        Idle.add( () => { 
            new_tab.tab = new Widgets.Tab();
            new_tab.tab.label = name;
            new_tab.tab.menu = tab_rightclick;
            new_tab.tab.ellipsize_mode = EllipsizeMode.NONE;

            if (new_tab.is_server_tab) {
                new_tab.tab.working = true;
                if (new_tab.connection.error_state) {
                    tabs.remove_tab(new_tab.tab);
                    return false;
                }
            }
            TextView output = new TextView();
            output.set_editable(false);
            output.set_cursor_visible(false);
            output.set_wrap_mode (Gtk.WrapMode.WORD_CHAR);
            output.set_left_margin(IRC.USER_WIDTH);
            output.set_indent(IRC.USER_WIDTH * -1);
            output.override_font(FontDescription.from_string("Inconsolata 9"));


            
            output.populate_popup.connect( (menu)=> {
                SeparatorMenuItem seperator = new SeparatorMenuItem();
                Gtk.MenuItem save_selection = new Gtk.MenuItem.with_label (_("Save Selection"));
                Gtk.MenuItem save_conversation = new Gtk.MenuItem.with_label (_("Save Conversation"));
                menu.add(seperator);
                menu.add(save_selection);
                menu.add(save_conversation);
                menu.show_all();
                if (!output.buffer.has_selection)
                    save_selection.set_sensitive(false);
                save_selection.activate.connect( ()=> {
                    TextIter start;
                    TextIter end;
                    output.buffer.get_selection_bounds(out start, out end);
                    save_output_to_file(output.buffer.get_text(start, end, false));
                });
                save_conversation.activate.connect( ()=> {
                    save_output_to_file(output.buffer.text);
                });
            });
            
            ScrolledWindow scrolled = new Gtk.ScrolledWindow (null, null);
            if (!Relay.on_ubuntu)
                scrolled.margin = 3;
            scrolled.add(output);

            var ptabs = new Pango.TabArray(1, true);
            ptabs.set_tab(0, Pango.TabAlign.LEFT, IRC.USER_WIDTH);
            output.tabs = ptabs;

            new_tab.tab.page = scrolled;
            new_tab.new_subject.connect(new_subject);
            tabs.insert_tab(new_tab.tab, -1); 

            new_tab.set_output(output);
            outputs.set(index, new_tab); 

            tabs.show_all();

            new_tab.tab_index = index;
            if (!new_tab.is_server_tab)
                new_tab.connection.server_tab.tab.working = false;

            if (tabs.n_tabs == 1) {
                tab_switch (null, new_tab.tab);
            }

            index++;
            if (items_sidebar.has_key(new_tab.tab.label))
                items_sidebar[new_tab.tab.label].icon = active_channel;

            if (settings.get_bool("change_tab"))
                tabs.current = new_tab.tab;

            rebuild_channel_list_menu();

            tabs.show_tabs = settings.get_bool("show_tabs");
            return false;
        });


        if (name != new_tab.connection.server.host)
            new_tab.connection.send_output("TOPIC " + name);
    }

    public void new_tab_requested () {
        var dialog = new Dialog.with_buttons(_("New Connection"), window,
            DialogFlags.DESTROY_WITH_PARENT,
            _("Connect"), Gtk.ResponseType.ACCEPT,
            "_Cancel", Gtk.ResponseType.CANCEL);
        Gtk.Box content = dialog.get_content_area() as Gtk.Box;
        content.pack_start(new Label(_("Server address")), false, false, 5);
        var server_name = new Entry();
        server_name.activate.connect(() => {
            dialog.response(Gtk.ResponseType.ACCEPT);
        });
        content.pack_start(server_name, false, false, 5);
        dialog.show_all();
        dialog.response.connect((id) => {
            switch (id){
                case Gtk.ResponseType.ACCEPT:
                    string name = server_name.get_text().strip();
                    if (name.length > 2) {
                        var server = new SqlClient.Server();
                        server.host = name;
                        server.nickname = server.username = Environment.get_user_name();
                        add_server(server);
                        dialog.close();
                    }
                    break;
                case Gtk.ResponseType.CANCEL:
                    dialog.close();
                    break;
            }
        });
    }

    private void tab_remove (Widgets.Tab tab) {  
        if (tab.label == _("Welcome"))
            return;

        int id = lookup_channel_id(tab);
        Connection tab_server = outputs[id].connection; 

        if (!outputs[id].is_server_tab)
            tab_server.send_output("PART " + outputs[id].channel_name);

        //Remove tab from the servers tab list
        tab_server.channel_tabs.unset(tab.label);

        //Remove server if no connections are left
        if (tab_server.channel_tabs.size < 1) {
            info("Closing server");
            tab_server.do_exit();
            clients.unset(tab_server.server.host);
        }

        //Remove the tab from the list of tabs
        outputs.unset(id);

        //Change the icon in the sidebar
        if (items_sidebar.has_key(tab.label))
            items_sidebar[tab.label].icon = inactive_channel;
        
        if (tabs.n_tabs == 0)
            show_welcome_screen();
    }

    private void tab_switch (Granite.Widgets.Tab? old_tab, Granite.Widgets.Tab new_tab) {
        if (old_tab != null && old_tab.label != _("Welcome")) {
            var last_tab = lookup_channel_id(old_tab);
            if (outputs.has_key(last_tab))
                outputs[last_tab].needs_spacer = true;
        }
        if (new_tab.label == _("Welcome")) {
            channel_subject.hide();
            channel_users.hide();
            input.hide();
            toolbar.set_title(app.program_name);
            toolbar.set_has_subtitle(false);
            toolbar.set_subtitle("");
            paste.hide();
            return;
        }
        
        input.show();

        new_tab.icon = null;

        current_tab = lookup_channel_id(new_tab);
        if (!outputs.has_key(current_tab))
            return;
        ChannelTab using_tab = outputs[current_tab];
        using_tab.needs_spacer = false;

        if (items_sidebar.has_key(using_tab.tab.label)) {
            items_sidebar[using_tab.tab.label].badge = "";
            refresh_icon(using_tab.message_count * -1);
            using_tab.message_count = 0;
            servers.selected = items_sidebar[using_tab.tab.label];
        }

        if (using_tab.has_subject) 
            new_subject(current_tab, using_tab.channel_subject.validate(-1) ? using_tab.channel_subject : using_tab.channel_subject.escape(""));
        else
            channel_subject.hide();

        if (using_tab.is_server_tab) {
            toolbar.set_title(using_tab.tab.label);
            toolbar.set_has_subtitle(false);
            toolbar.set_subtitle("");
            channel_users.hide();
            paste.hide();
        } else {
            paste.show();
            toolbar.set_title(using_tab.tab.label);
            toolbar.set_subtitle(using_tab.connection.server.host);
            toolbar.has_subtitle = (using_tab.tab.label != using_tab.connection.server.host);

            input.placeholder_text = using_tab.tab.label;

            if (using_tab.users.size < 1)
                channel_users.hide();
            else
                channel_users.show_all();
        }
    }

    private void make_user_popover (string search_str = "", bool need_show = false) {
        users_header.set_text(_("Loading..."));
        if (need_show)
            users_popover.show_all();
        users_list.hide();
        new Thread<int> ("User popover", ()=> {
            make_user_popover_idle(outputs.get(current_tab), search_str);
            return 0;
        });
    }
    
    private int invoke_count = 0;
    private void make_user_popover_idle (ChannelTab? using_tab, string _search_str = "") {
        if (_search_str == "") {
            invoke_count++;
        } else {
            invoke_count++;
            int current_invoke_cnt = invoke_count;
            Thread.usleep(500000);
            if (current_invoke_cnt != invoke_count)
                return;
        
            if (using_tab == null)
                return;
        }

        string search_str = _search_str.down();

        int PER_BOX = 15;
        int BOX_WIDTH = 140;
        int MAX_COLS = 4;
        int type_change = 0;
        LinkedList<LinkedList<string>> user_types;
        if (search_str != "") {
            LinkedList<LinkedList<string>> _user_types = using_tab.get_all_user_lists();
            user_types = new LinkedList<LinkedList<string>>();
            foreach (var _list in _user_types) {
                var list = new LinkedList<string>();
                foreach (string usr in _list)
                    if (usr.down().contains(search_str))
                        list.add(usr);
                user_types.add(list);
            }
        }else{
            user_types = using_tab.get_all_user_lists();
        }
        
        int total_size = using_tab.users.size + using_tab.owners.size + using_tab.ops.size + using_tab.half_ops.size;

        //Make users
        LinkedList<EventBox> list_boxes = new LinkedList<EventBox>();
        foreach(Gee.List<string> type in user_types) {
            foreach (string user in type) {
                list_boxes.add(make_user_eventbox(user, type_change));
            }
            type_change++;
        }

        LinkedList<Box> lb_wrappers = new LinkedList<Box>();
        var listbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        listbox.width_request = BOX_WIDTH;
        
        int i = 0;
        foreach (var box in list_boxes) {
            i++;
            listbox.pack_start(box, false, false, 0);
            if (i % PER_BOX == 0 && total_size >= i) {
                listbox.width_request = BOX_WIDTH;
                lb_wrappers.add(listbox);
                listbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            }
        }
        lb_wrappers.add(listbox);

        Idle.add( ()=>{
            foreach (var box in users_list.get_children())
                users_list.remove(box);
            
            
            foreach (var wrapper in lb_wrappers) {
                users_list.pack_start(wrapper, true, true, 0);
            }
            
            users_list.show_all();

            users_header.set_text(_("Total users: ") + i.to_string());

            int cols = (int) Math.ceilf((float)i / (float)PER_BOX); 
            users_scrolled.min_content_width = (cols > MAX_COLS) ? BOX_WIDTH * MAX_COLS : cols * BOX_WIDTH;
            return false;
        });
    }

    private EventBox make_user_eventbox (string user, int type = -1) {
        var eb = new EventBox();
        eb.enter_notify_event.connect( ()=> {
            eb.set_state_flags(StateFlags.PRELIGHT | StateFlags.SELECTED, true);
            return false;
        });
        eb.leave_notify_event.connect( ()=> {
            eb.set_state_flags(StateFlags.NORMAL, true);
            return false;
        });
        var label = new Label("");
        var color = RGBA();
        if (type == 0) {
            color.parse("#00D901");
            label.set_tooltip_text(_("Owner"));
            label.override_color(StateFlags.NORMAL, color);
        } else if (type == 1) {
            color.parse("#F5E219");
            label.set_tooltip_text(_("Operator"));
            label.override_color(StateFlags.NORMAL, color);
        } else if (type == 2) {
            color.parse("#9A19F5");
            label.set_tooltip_text(_("Half Operator"));
            label.override_color(StateFlags.NORMAL, color);
        } else if (outputs[current_tab].blocked_users.contains(user)) {
            color.parse("#FF0000");
            label.override_color(StateFlags.NORMAL, color);
        }
        label.set_text(user);
        label.width_chars = IRC.USER_LENGTH;
        label.margin_top = label.margin_bottom = 4;
        eb.add(label);
        eb.button_press_event.connect( (event)=> {
            if (event.button == 3) {
                channel_user_selected = user;
                user_menu.popup (null, null, null, event.button, event.time);
            } else if (event.button == 1) {
                MainWindow.fill_input(user + ": ");
            }
            return true;
        });
        return eb;
    }

    private bool click_private_message (Gdk.EventButton event) {
        info("Selected user is " + channel_user_selected);
        user_menu.popdown();
        users_popover.set_visible(false);
        ChannelTab using_tab = outputs[current_tab];
        ChannelTab user_tab = using_tab.connection.add_channel_tab(IRC.remove_user_prefix(channel_user_selected));
        tabs.current = user_tab.tab;
        return false;
    }

    private bool click_block (Gdk.EventButton event) {
        user_menu.popdown();
        ChannelTab using_tab = outputs[current_tab];
        if (using_tab.blocked_users.contains(channel_user_selected))
            using_tab.remove_block_list(channel_user_selected);
        else
            using_tab.add_block_list(channel_user_selected);
        users_popover.set_visible(false);
        return false;
    }

    public void add_server (SqlClient.Server server, LinkedList<string>? connect_channels = null) {
        var connection = new Connection();
        clients.set(server.host, connection); 
        connection.new_tab.connect(add_tab);
        connection.new_message.connect(add_text);
        connection.change_channel_state.connect(sidebar_state);

        if (connect_channels != null)
            connection.channel_autoconnect = connect_channels;

        connection.connect_to_server(server);
    }

    private void sidebar_state (string name, string state) {
        if (!items_sidebar.has_key(name))
            return;

        Icon pixbuf = inactive_channel;
        switch (state) {
            case "active":
                pixbuf = active_channel;
                break;
            case "loading":
                pixbuf = loading_channel;
                break;
            case "stuck":
                if (items_sidebar[name].icon != loading_channel)
                    return;
                pixbuf = inactive_channel;
                break;
        }
        items_sidebar[name].icon = pixbuf;
    }

    public void refresh_server_list () {
        var root = servers.root;
        root.clear();

        var new_items_sidebar = new HashMap<string, Widgets.SourceList.Item>();

        foreach (var svr in SqlClient.servers.entries) {
            var s =  new Widgets.SourceList.ExpandableItem(svr.value.host);
            root.add(s);
            var chn = new Widgets.SourceList.Item(svr.value.host);
            chn.set_data<string>("type", "server");
            chn.set_data<SqlClient.Server>("server", svr.value);
            chn.icon = (items_sidebar.has_key(svr.value.host)) ? items_sidebar[svr.value.host].icon : inactive_channel;
            s.add(chn);
            new_items_sidebar[svr.value.host] = chn;

            foreach (var c in svr.value.channels) {
                chn = new Granite.Widgets.SourceList.Item(c.channel);
                chn.set_data<string>("type", "channel");
                chn.set_data<SqlClient.Channel>("channel", c);
                chn.activated.connect(sidebar_item_activated);
                chn.icon = (items_sidebar.has_key(c.channel)) ? items_sidebar[c.channel].icon : inactive_channel;
                s.add(chn);
                new_items_sidebar[c.channel] = chn;
            }
        }
        items_sidebar = new_items_sidebar;
    }

    /* 
     * Called when an an item on the sidebar is double clicked
     */
    private void sidebar_item_activated () {
        string type = current_selected_item.get_data<string>("type");
        if (type == "server") {
            //Has existing server
            SqlClient.Server server = current_selected_item.get_data<SqlClient.Server>("server");
            foreach (var tab in outputs.entries) {
                if (tab.value.is_server_tab && tab.value.channel_name == server.host) {
                    tabs.current = tab.value.tab;
                    return;
                }
            }
            //No existing server
            add_server(server);
        } else {
            //Existing channel tab
            SqlClient.Channel channel = current_selected_item.get_data<SqlClient.Channel>("channel");
            var server = SqlClient.servers[channel.server_id];
            foreach (var tab in outputs.entries) {
                if (!tab.value.is_server_tab && 
                    tab.value.tab.label == channel.channel &&
                    server.host == tab.value.connection.server.host) {
                    tabs.current = tab.value.tab;
                    return;
                }
            } 
            
            //Has existing server but no channel
            foreach (var con in clients.entries) {
                if (con.key == server.host) {
                    if (!con.value.autoconnect_ran && !con.value.channel_autoconnect.contains(channel.channel)) {
                        items_sidebar[channel.channel].icon = loading_channel;
                        con.value.channel_autoconnect.add(channel.channel);
                    } else
                        con.value.join(channel.channel);
                    return;
                }
            }
            //Has no existing server or channel
            items_sidebar[channel.channel].icon = loading_channel;
            LinkedList<string> channels = new LinkedList<string>();
            channels.add(channel.channel);
            add_server(SqlClient.servers[channel.server_id], channels);
        }
    } 

    public void add_text (ChannelTab? tab, Message message, bool error = false) {
        if (tab == null)
            return;
        else if (tab.needs_spacer) {
            if (tab.get_char_count() > 3 && settings.get_bool("show_line"))
                tab.add_spacer_line();
            tab.needs_spacer = false;
        }
        
        if (error) {
            message.message = _("Error: ") + message.message;
            tab.display_error(message);
        } else
            tab.display_message(message);


        if (current_tab != tab.tab_index && !tab.is_server_tab) {       
            tab.message_count++;

            Idle.add( ()=> {
                if (items_sidebar.has_key(tab.tab.label))
                    items_sidebar[tab.tab.label].badge = tab.message_count.to_string();

                tab.tab.icon = channel_tab_icon_new_msg;

                refresh_icon(1);

                return false;
            });

        }
    }

    public void refresh_icon (int add) {
        launcher.count += add;
        launcher.count_visible = (launcher.count > 0);
        launcher.urgent = true;
        launcher.urgent = false;
    }

    public void send_text_out (string text) {
        if (current_tab == -1 || !outputs.has_key(current_tab) || text == "")
            return;
        var output = outputs[current_tab]; 
        output.send_text_out(text);

        var message = new Message();

        //Append message to screen
        message.user_name_set(output.connection.server.nickname);
        message.message = text;
        message.command = "PRIVMSG";
        message.internal = true;
        add_text(output, message); 
        return; 
    }

    int sliding = 0;
    public bool slide_panel () {
        if (settings.get_bool("show_animations")) {
            if (sliding > 1)
                return false;
            new Thread<int>("slider_move", move_slider_t);
        } else {
            panel.set_position(panel.position < 10 ? 180 : 0);
        }
        return false;
    }

    public int move_slider_t () {
        sliding++;
        while (sliding > 1)
            Thread.usleep(1000);
        int add, end, go_to, pos;
        bool opening;
        opening = (panel.position < 10);
        end = opening ? 550 : 618;
        add = 1;
        go_to = 180;
        for (int i = panel.position; i < end; i+= add) {
            if (opening) {
                pos = (int) Relay.ease_out_elastic(i, 0.0F, go_to, end);
                if (i > 420) 
                    break;
            } else {
                pos = (int) Relay.ease_in_bounce(end - i, 0.0F, go_to, end);
            }

            panel.set_position(pos);
            Thread.usleep(3600);
        }
        sliding--;
        return 0;
    }

    public int lookup_channel_id (Widgets.Tab tab) {
        foreach (var output in outputs.entries) { 
            if (output.value.tab == tab) {
                return output.value.tab_index;
            }
        }
        return -1;
    }

    private void new_subject (int tab_id, string message) {
        if (tab_id != current_tab || message.strip().length == 0) {
            return;
        }
        /*
        var rich_text = new RichText(message);
        rich_text.parse_links();
        string new_string = "";
        int last_pos = 0;
        string msg = message;
        for(int i = 0; i < rich_text.link_locations_start.size; i++) {
            int start = message.length - rich_text.link_locations_start[i];
            int end = message.length - (rich_text.link_locations_end[i]);
            string link = msg.substring(start, end - start);
            int space = start - last_pos;
            string add = msg.substring(last_pos, space) + "<a href=\"" + link + "\">" + link + "</a>";
            last_pos = end;
            new_string += add;
        }
        new_string += message.substring(last_pos);
        */
        string url = (outputs[tab_id].channel_url != "") ? "\n\n" + outputs[tab_id].channel_url : "";
        subject_text.set_text(message + url);
        channel_subject.show();
    }

    public static void fill_input (string message) {
        MainWindow.input.set_text(message);
        MainWindow.input.is_focus = true;
        MainWindow.input.select_region(message.length, message.length);
    }

    public void file_uploaded(string url) {
        MainWindow.input.set_text(MainWindow.input.get_text() + " " + url);
    }

    private void load_autoconnect () {
        bool opened_tab = false;

        foreach (var server in SqlClient.servers.entries) {
            var to_connect = server.value.get_autoconnect_channels();
            if (to_connect.size > 0) {
                opened_tab = true;
                add_server(server.value, to_connect);
            }
        }

        if (!opened_tab)
            show_welcome_screen();
    }

    private void show_welcome_screen () {
        var title = _("Welcome to Relay");
        var message =  _("Lets get started");
        var welcome = new Widgets.Welcome(title, message);
        welcome.append_with_image(new Image.from_file(Relay.get_asset_file("assets/manage-servers.png")), _("Manage"), _("Manage the servers you use"));
        welcome.append_with_image(new Image.from_file(Relay.get_asset_file("assets/connect-server.png")), _("Connect"), _("Connect to a single server"));
        welcome.append_with_image(new Image.from_file(Relay.get_asset_file("assets/saved-server.png")), _("Saved"), _(settings.get_bool("show_sidebar") ? _("Your sidepanel is already open") : _("Connect to a saved server")));

        var tab = new Widgets.Tab();
        tab.icon = null;
        tab.label = _("Welcome");
        toolbar.set_title(app.program_name);
        toolbar.set_subtitle("");
        toolbar.set_has_subtitle(false);
        tab.page = welcome;
        tabs.insert_tab(tab, -1);
        tabs.show_tabs = settings.get_bool("show_tabs");

        welcome.activated.connect( (index) => {
            switch (index) {
                case 0:
                    server_manager.open_window();
                    return;
                case 1:
                    new_tab_requested();
                    return;
                case 2:
                    slide_panel();
                    return;
            }
        });
    }

    public void set_up_add_sever (Builder builder) {
        var add_server_button = builder.get_object("manage_servers") as Button;

        add_server_button.button_release_event.connect( (event) => {
            server_manager.open_window();
            return false;
        });
    }

    public void tags_refresh () {
        outputs.foreach( (tab)=> {
            var usetab = tab;
            usetab.value.update_tag_table();
            return true;
        });
    }

    private void save_output_to_file (string text) {
            Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
                    _("Save the conversation"), window, Gtk.FileChooserAction.SAVE,
                    "_Cancel",
                    Gtk.ResponseType.CANCEL,
                    "_Save",
                    Gtk.ResponseType.ACCEPT,
                    null);
            chooser.do_overwrite_confirmation = true;
            chooser.set_filename(outputs[current_tab].channel_name);
            chooser.set_current_folder(Environment.get_home_dir());
            int resp = chooser.run();
            if  (resp == Gtk.ResponseType.ACCEPT) {
                try{
                    FileUtils.set_contents(chooser.get_filename(), text);
                } catch (FileError e) {
                    Relay.show_error_window(e.message);
                }
                chooser.close ();
            }else {
                chooser.close ();
            }
    }
    
    private void editPreferencesClick () {
        settings.show_window ();
    }

    public void relay_close_program () { 
        foreach(var client in clients.entries) {
            client.value.do_exit();
        }
        GLib.Process.exit(0);
    }

    [CCode (instance_pos = -1)]
    public void on_destroy (Widget window) {
        Gtk.main_quit();
    }
}

