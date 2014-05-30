import derelictsdl2_ext;
import derelict.util.system;
import derelict.sdl2.types;

version(Windows)
{
extern(Windows)
{
    DWORD MsgWaitForMultipleObjects(DWORD, const(HANDLE) *, BOOL, DWORD, DWORD);
    BOOL PostMessage(HWND, UINT, WPARAM, LPARAM);
    enum QS_ALLEVENTS = 0x04BF;
    enum INFINITE = uint.max;
    enum WAIT_TIMEOUT = 258L;
    enum WAIT_FAILED = 0xFFFFFFFF;
    enum WM_NULL = null;
}
bool EXT_WaitEvent(SDL_Window* window, int timeout)
{
    DWORD tv;
    if (timeout < 0)
        tv = INFINITE;
    else
        tv = timeout;

    DWORD ret = MsgWaitForMultipleObjects(0, null, false, tv, QS_ALLEVENTS);
    if (ret == WAIT_TIMEOUT || ret == WAIT_FAILED)
        return false;
    return true;
}
void EXT_PostEmptyEvent(SDL_Window* window)
{
    SDL_SysWMinfo wmInfo;
    SDL_VERSION(&wmInfo._version);

    auto gotWMInfo = SDL_GetWindowWMInfo(window, &wmInfo);
    assert(gotWMInfo != SDL_FALSE, "Couldn't get WMInfo\n");

    PostMessage(wmInfo.info.win.window, WM_NULL, 0, 0);
}
}
else
static if(Derelict_OS_Posix && !Derelict_OS_Mac)
{
import core.sys.posix.sys.select;

bool EXT_WaitEvent(SDL_Window* window, int timeout)
{
    SDL_SysWMinfo wmInfo;
    SDL_VERSION(&wmInfo._version);

    auto gotWMInfo = SDL_GetWindowWMInfo(window, &wmInfo);
    assert(gotWMInfo != SDL_FALSE, "Couldn't get WMInfo\n");
    assert(wmInfo.subsystem == SDL_SYSWM_TYPE.SDL_SYSWM_X11, "EXT_WaitEvent assumes X11\n");

    import x11.Xlib : XPending, ConnectionNumber;
    if (XPending(wmInfo.info.x11.display))
        return true;

    fd_set fds;
    int fd = ConnectionNumber(wmInfo.info.x11.display);

    FD_ZERO(&fds);
    FD_SET(fd, &fds);

    if (timeout < 0)
    {
        return select(fd + 1, &fds, null, null, null) > 0;
    }
    else
    {
        timeval tv = {0, timeout*1000};
        return select(fd + 1, &fds, null, null, &tv) > 0;
    }
    // TODO: use peepevents to loop when timeout < 0
}

void EXT_PostEmptyEvent(SDL_Window* window)
{
    SDL_SysWMinfo wmInfo;
    SDL_VERSION(&wmInfo._version);

    auto gotWMInfo = SDL_GetWindowWMInfo(window, &wmInfo);
    assert(gotWMInfo != SDL_FALSE, "Couldn't get WMInfo\n");

    import x11.X : ClientMessage;
    import x11.Xlib : XEvent, XFlush, XSendEvent;
    enum False = 0;
    XEvent event;
    //memset(&event, 0, sizeof(event));
    event.type = ClientMessage;
    event.xclient.window = wmInfo.info.x11.window;
    event.xclient.format = 32; // Data is 32-bit longs
    event.xclient.message_type = 0;

    XSendEvent(wmInfo.info.x11.display, wmInfo.info.x11.window, False, 0, &event);
    XFlush(wmInfo.info.x11.display);
}
}
else
{
    static assert(false,"Platform support not implemented");
}