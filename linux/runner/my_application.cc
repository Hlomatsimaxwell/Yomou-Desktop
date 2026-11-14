#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* app_icon_channel;
  FlMethodChannel* window_channel;
};

// Best-effort icon for the first frames, before Dart applies the variant the
// user picked. Installed packages resolve APPLICATION_ID through the icon
// theme; AppImages keep the PNG at the AppDir root and set $APPDIR.
static void apply_startup_icon(GtkWindow* window) {
  const gchar* appdir = g_getenv("APPDIR");
  if (appdir != nullptr && *appdir != '\0') {
    g_autofree gchar* path =
        g_build_filename(appdir, APPLICATION_ID ".png", nullptr);
    g_autoptr(GError) error = nullptr;
    if (gtk_window_set_icon_from_file(window, path, &error)) {
      return;
    }
    g_clear_error(&error);
  }
  gtk_window_set_icon_name(window, APPLICATION_ID);
}

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Handles the app-icon channel shared with lib/core/app_icon/app_icon_service.dart.
// Linux uses it to swap the live window icon when the user picks a variant; the
// launcher entry is rewritten on the Dart side.
static void app_icon_method_call(FlMethodChannel* channel,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(fl_method_call_get_name(method_call), "setWindowIcon") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* path = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      path = fl_value_lookup_string(args, "path");
    }

    gboolean applied = FALSE;
    if (path != nullptr && fl_value_get_type(path) == FL_VALUE_TYPE_STRING &&
        self->window != nullptr) {
      g_autoptr(GError) error = nullptr;
      applied = gtk_window_set_icon_from_file(
          self->window, fl_value_get_string(path), &error);
      if (error != nullptr) {
        g_warning("Failed to set window icon: %s", error->message);
      }
    }

    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(applied)));
  }

  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Handles the window channel from lib/core/window/desktop_window_service.dart.
// The header bar is GTK chrome, not Flutter content, so its colours come from
// the GTK theme. The app tells GTK which variant it is using so the title bar
// stays in step with an explicit light/dark choice as well as the system one.
static void window_method_call(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(fl_method_call_get_name(method_call), "setDarkTheme") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* dark_value = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      dark_value = fl_value_lookup_string(args, "dark");
    }

    gboolean dark = FALSE;
    if (dark_value != nullptr &&
        fl_value_get_type(dark_value) == FL_VALUE_TYPE_BOOL) {
      dark = fl_value_get_bool(dark_value);
    }

    GtkSettings* settings = gtk_settings_get_default();
    gboolean applied = FALSE;
    if (settings != nullptr) {
      g_object_set(settings, "gtk-application-prefer-dark-theme", dark,
                   nullptr);
      applied = TRUE;
    }

    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(applied)));
  }

  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  self->window = window;

  // Show the app name in the window chrome. With a header bar the title has to
  // be set on the bar itself; otherwise the window manager draws the title.
  apply_startup_icon(window);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Yomou");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Yomou");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  self->app_icon_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.hlomatsi.yomou/app_icon",
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(
      self->app_icon_channel, app_icon_method_call, self, nullptr);

  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine),
      "com.hlomatsi.yomou/window",
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->app_icon_channel);
  g_clear_object(&self->window_channel);
  self->window = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
