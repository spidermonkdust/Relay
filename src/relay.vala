/* -*- Mode: vala; indent-tabs-mode: nil; c-basic-offset: 4; tab-width: 4 -*-  */
/*
 * relay.vala
 * Copyright (C) 2015 Kyle Agronick <agronick@gmail.com>
 *
 * relay is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * relay is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
using X;

public class Relay : Granite.Application {

        private MainWindow window = null;
        public string[] args;
        public static bool has_activated = false;

        construct {
            program_name = "Relay";
            exec_name = "relay";

            build_data_dir = Config.PACKAGE_DATA_DIR;
            build_pkg_data_dir = Config.GETTEXT_PACKAGE;
            build_version = Config.VERSION;

            app_years = "2015";
            app_icon = "relay";
            app_launcher = "relay.desktop";
            application_id = "net.launchpad.relay";

            main_url = "http://poisonpacket.wordpress.com";
            bug_url = "https://bugs.launchpad.net/relay";
            help_url = "http://poisonpacket.wordpress.com";
            translate_url = "https://translations.launchpad.net/relay";

            about_authors = { "Kyle Agronick <agronick@gmail.com>" };
            about_documenters = { "Kyle Agronick <agronick@gmail.com>" };
            about_artists = { "Kyle Agronick (App) <agronick@gmail.com>" };
            about_comments = "IRC Client for the Modern Desktop";
            about_translators = "translator-credits";
            about_license_type = Gtk.License.GPL_3_0;

            set_options();

            Intl.setlocale(LocaleCategory.MESSAGES, "");
            Intl.textdomain(Config.GETTEXT_PACKAGE); 
            Intl.bind_textdomain_codeset(Config.GETTEXT_PACKAGE, "utf-8"); 
            Intl.bindtextdomain(Config.GETTEXT_PACKAGE, "./locale");
        }


    /* Method definitions */
    public static void main (string[] args) {
        X.init_threads ();
        Gtk.Settings.get_default().set("gtk-application-prefer-dark-theme", true);
        
        GLib.Log.set_default_handler(handle_log);

        var main = new Relay();
        main.run(args);
    }

    public override void activate () {

        if (has_activated) {
            window.window.present();
            return;
        }

        has_activated = true;

        Gtk.Settings.get_default().gtk_application_prefer_dark_theme = true;

        window = new MainWindow();
        Gtk.main ();
    }

    public static void handle_log (string? log_domain, LogLevelFlags log_levels, string message) {
        string prefix = "";
        string suffix = "\x1b[39;49m " ;
        switch(log_levels) {
            case LogLevelFlags.LEVEL_DEBUG:
                prefix = "\x1b[94mDebug: ";
                break;
            case LogLevelFlags.LEVEL_INFO:
                prefix = "\x1b[92mInfo: ";
                break;
            case LogLevelFlags.LEVEL_WARNING:
                prefix = "\x1b[93mWarning: ";
                break;
            case LogLevelFlags.LEVEL_ERROR:
                prefix = "\x1b[91mError: ";
                break;
            default:
                prefix = message;
                break;
        }
        GLib.stdout.printf(prefix + message + suffix + "\n");
    }
}

