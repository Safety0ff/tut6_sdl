import derelict.util.system;
private import derelict.util.xtypes;
private import derelict.util.wintypes;
import derelict.sdl2.sdl;

// Ext for types.d
enum SDL_SYSWM_TYPE
{
    SDL_SYSWM_UNKNOWN,
    SDL_SYSWM_WINDOWS,
    SDL_SYSWM_X11,
    SDL_SYSWM_DIRECTFB,
    SDL_SYSWM_COCOA,
    SDL_SYSWM_UIKIT,
    SDL_SYSWM_WAYLAND,
    SDL_SYSWM_MIR,
    SDL_SYSWM_WINRT,
}

struct SDL_SysWMinfo
{
    SDL_version _version; // version is reserved in D
    SDL_SYSWM_TYPE subsystem;

    static union _info
    {
version(Windows)
{
        struct _win
        {
            HWND window;
        } _win win;
        struct winrt
        {
            void* window;
        }
}
static if (Derelict_OS_Posix)
{
        struct _x11
        {    import x11.Xlib : Display;
            import x11.X : Window;
            Display *display;
            Window window;
        } _x11 x11;
        struct _dfb
        {
            void *dfb;
            void *window;
            void *surface;
        } _dfb dfb;
}
version(OSX)
{
        struct _cocoa
        {
            void* window;
        } _cocoa cocoa;
}
        struct _uikit
        {
            void *window;
        } _uikit uikit;
        struct _wl
        {
            void *display;
            void *surface;
            void *shell_surface;
        } _wl wl;
        struct _mir
        {
            void *connection;
            void *surface;
        } _mir mir;
        int dummy;
    } _info info;
}

// Ext for functions.d
extern(C) nothrow {
    // SDL_syswm.h
    alias da_SDL_GetWindowWMInfo = SDL_bool function(SDL_Window*, SDL_SysWMinfo*);
}

__gshared {
    da_SDL_GetWindowWMInfo SDL_GetWindowWMInfo;
}

class DerelictSDL2EXTLoader : DerelictSDL2Loader
{
    protected override void loadSymbols() {
        bindFunc(cast(void**)&SDL_GetWindowWMInfo, "SDL_GetWindowWMInfo");
    }
}
__gshared DerelictSDL2EXTLoader DerelictSDL2EXT;

shared static this() {
    DerelictSDL2EXT = new DerelictSDL2EXTLoader();
}