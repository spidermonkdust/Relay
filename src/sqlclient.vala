/*
 * sqlclient.vala
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
using GLib.Environment;
using Sqlite;
using Gee;

public class SqlClient : Object
{
    public const string DB_FILE = "relay02.db";
    static SqlClient self = null;
    public static Sqlite.Database db;
    public static HashMap<int, Server> servers = new HashMap<int, Server>();

    private SqlClient () {
        init();
    }

    public static SqlClient get_instance () {
        if (self == null)
            self = new SqlClient();

        return self;
    }

    public HashMap<int, Server> get_servers() {
        return servers;
    }

    private void init () {
        string confbase = GLib.Environment.get_user_config_dir() + "/relay";
        File dir = File.new_for_path(confbase);
        try{
            if (!dir.query_exists())
                dir.make_directory();
        }catch(Error e){
            error("Unable to create database. Can not write to " + confbase + ". Program will not function.");
        }

        string conffile = confbase + "/" + DB_FILE;

        int ec = Sqlite.Database.open_v2(conffile, out db);
        if (ec != Sqlite.OK) {
            stderr.printf ("Can't open database: %d: %s\n", db.errcode (), db.errmsg ());
        }

        add_tables();
        refresh();
    }

    public void refresh () {
        servers.clear();
        db.exec("SELECT * from servers ORDER BY servers.host", refresh_callback);
        db.exec("SELECT * from channels ORDER BY channels.channel", refresh_callback_channel);
    }

    public Server? get_server (string name) {
        foreach (var svr in servers.entries) {
            if (svr.value.host == name)
                return svr.value;
        }
        return null;
    }

    public Server? get_server_id (int id) {
        if (servers.has_key(id))
            return servers[id];
        return null;
    }

    public static Channel? find_channel (Server current_server,  string name) {
        foreach (var chan in current_server.channels) {
            if (chan.server_id == current_server.id && chan.channel == name)
                return chan;
        }
        return null;
    }

    public int refresh_callback (int n_columns, string[] values, string[] column_names) {
        var server = new Server();
        for (int i = 0; i < n_columns; i++) {
            switch(column_names[i]) {
                case "id":
                    server.id = int.parse(values[i]);
                    break;
                case "host":
                    server.host = values[i];
                    break;
                case "port":
                    server.port =  int.parse(values[i]);
                    break;
                case "nickname":
                    server.nickname = values[i];
                    break;
                case "realname":
                    server.realname = values[i];
                    break;
                case "username":
                    server.username = values[i];
                    break;
                case "password":
                    server.password = values[i];
                    break;
                case "on_connect":
                    server.on_connect = values[i];
                    break;
                case "encryption":
                    server.encryption = to_bool(values[i]);
                    break;
                case "validate_server":
                    server.validate_server = to_bool(values[i]);
                    break;
                case "autoconnect":
                    server.autoconnect = to_bool(values[i]);
                    break;
                case "connect_cmds":
                    server.connect_cmds = values[i];
                    break;
                default:
                    warning("Not able to handle col: " + column_names[i]);
                    break;
            }
        }
        servers[server.id] = server;
        return 0;
    }

    public int refresh_callback_channel (int n_columns, string[] values, string[] column_names) {
        Server svr = null;
        for (int i = 0; i < n_columns; i++) {
            if (column_names[i] == "server_id") {
                svr = get_server_id( int.parse(values[i]));
            }
        }

        if (svr == null)
            return 0;

        Channel chn = new Channel();
        for (int i = 0; i < n_columns; i++) {
            switch(column_names[i]) {
                case "id":
                    chn.id = int.parse(values[i]);
                    break;
                case "server_id":
                    chn.server_id = int.parse(values[i]);
                    break;
                case "channel":
                    chn.channel = values[i];
                    break;
                case "autoconnect":
                    chn.autoconnect = to_bool(values[i]);
                    break;
            }
        }


        svr.channels.add(chn);

        return 0;
    }

    public static bool to_bool (string? input) {
        if (input == null)
            return false;
        return (input == "1");
    }

    public static int bool_to (bool b) {
        return b ? 1 : 0;
    }

    public class Server{

        public const string[] keys = {"host", "port", "nickname", "realname", "username", "password", "on_connect", "encryption", "validate_server", "autoconnect", "connect_cmds"};

        public int id = -1;
        public string host = "";
        public int port = Connection.DEFAULT_PORT;
        public string nickname = "";
        public string realname = "";
        public string username = "";
        public string password = "";
        public string on_connect = "";
        public bool encryption = false;
        public bool autoconnect = false;
        public bool validate_server = false;
        public string connect_cmds = "";
        public LinkedList<Channel> channels = new LinkedList<Channel>();

        public int add_server_empty () {
            string sql = "INSERT INTO servers (host, port) VALUES('', " + Connection.DEFAULT_PORT.to_string() + ")";
            db.exec(sql);
            this.id = (int)db.last_insert_rowid ();
            servers[this.id]=this;
            return this.id;
        }

        public int add_server () {
            this.id = add_server_empty ();
            servers[id]=this;
            update();
            return id;
        }

        public Channel? find_channel_by_name (string name) {
            foreach(Channel chan in channels) {
                if (chan.channel == name)
                    return chan;
            }
            return null;
        }

        public LinkedList<string> get_autoconnect_channels() {
            var returns = new LinkedList<string>();
            foreach(var channel in channels) {
                if (channel.autoconnect)
                    returns.add(channel.channel);
            }
            return returns;
        }

        public int update () {
            var svr = this;
            Sqlite.Statement stmt;
            int ok;
            string sql = "SELECT id FROM servers WHERE id = " + svr.id.to_string();
            bool exists = false;
            db.exec(sql, (n_columns, values, column_names) => {
                exists = true;
                return 0;
            });


            string keys = "";
            foreach (string i in Server.keys) {
                //Skip over ID
                if (keys == "") {
                    keys = " ";

                }
                keys += i + "=$" + i + ", ";
            }

            keys = keys[0:-2];


            if (exists) {
                sql = "UPDATE servers SET " + keys + " WHERE id = " + svr.id.to_string();

                ok = db.prepare_v2(sql, sql.length, out stmt);
                if (ok != Sqlite.OK) {
                    critical (db.errmsg ());
                    return -1;
                }

                stmt.bind_text(1, svr.host);
                stmt.bind_int(2, svr.port);
                stmt.bind_text(3, svr.nickname);
                stmt.bind_text(4, svr.realname);
                stmt.bind_text(5, svr.username);
                stmt.bind_text(6, svr.password);
                stmt.bind_text(7, svr.on_connect);
                stmt.bind_int(8, bool_to(svr.encryption));
                stmt.bind_int(9, bool_to(svr.validate_server));
                stmt.bind_int(10, bool_to(svr.autoconnect));
                stmt.bind_text(11, svr.connect_cmds);

                stmt.step();

                SqlClient.servers[svr.id] = svr;


            }

            return 0;
        }

        public void remove_server () {
            servers.unset(this.id);
            string sql = "DELETE FROM servers WHERE id=" + this.id.to_string();
            db.exec(sql);
            sql = "DELETE FROM channels WHERE server_id=" + this.id.to_string();
            db.exec(sql);
        }
    }

    public class Channel{
        public int id = -1;
        public int server_id;
        public string channel;
        public bool autoconnect;

        public void delete_channel () {
            string sql = "DELETE FROM channels WHERE server_id=" + this.server_id.to_string() + " AND channel=$NAME";
            channel_query(sql);
            if (!servers.has_key(server_id)) {
                warning("No server with key " + server_id.to_string());
                return;
            }
            servers[server_id].channels.remove(this);
        }

        public void add_channel () {
            if (this.server_id < 0)
                return;
            string sql = "INSERT INTO channels (server_id, channel) VALUES(" + this.server_id.to_string() + ", $CHANNEL)";
            channel_query(sql);
            servers[server_id].channels.add(this);
        }

        public bool update_autoconnect (bool state) {
            string sql = "UPDATE channels SET autoconnect = " + bool_to (state).to_string() + " WHERE server_id = " + server_id.to_string() + " AND channel = $NAME";
            channel_query(sql);
            autoconnect = state;
            return autoconnect;
        }

        private void channel_query (string sql) {
            Sqlite.Statement stmt;
            int ok = db.prepare_v2(sql, sql.length, out stmt);
            if (ok == Sqlite.ERROR) {
                critical (db.errmsg ());
                return;
            }
            stmt.bind_text(1, this.channel);
            stmt.step();
        }
    }


    private void add_tables () {
        string sql = """
        CREATE TABLE IF NOT EXISTS "servers" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "host" TEXT NOT NULL,
        "port" INTEGER NOT NULL,
        "nickname" TEXT,
        "realname" TEXT,
        "username" TEXT,
        "password" TEXT,
        "on_connect" TEXT,
        "connect_cmds" TEXT,
        "encryption" BOOL,
        "autoconnect" BOOL,
        "validate_server" BOOL
        );

        CREATE TABLE IF NOT EXISTS "channels" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "server_id" INTEGER,
        "channel" TEXT,
        "autoconnect" BOOL
        );
        """;

        db.exec(sql);
    }
}
