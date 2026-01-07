#+build darwin

package karl2d

import gl "vendor:OpenGL"
import "vendor:glfw"

GL_Context :: glfw.WindowHandle

_gl_get_context :: proc(window_handle: Window_Handle) -> (GL_Context, bool) {
	window := glfw.WindowHandle(window_handle)
	if window == nil {
		return nil, false
	}

	// Context is already current from window creation in GLFW
	// Just return the window handle as our "context"
	return window, true
}

_gl_destroy_context :: proc(ctx: GL_Context) {
	// GLFW handles context destruction when window is destroyed
	// Nothing to do here
}

_gl_load_procs :: proc() {
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)
}

_gl_present :: proc(window_handle: Window_Handle) {
	window := glfw.WindowHandle(window_handle)
	glfw.SwapBuffers(window)
}
