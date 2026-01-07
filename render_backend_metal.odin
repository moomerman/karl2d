#+build darwin
#+private file

package karl2d

import "core:fmt"

@(private = "package")
RENDER_BACKEND_METAL :: Render_Backend_Interface {
	state_size                     = metal_state_size,
	init                           = metal_init,
	shutdown                       = metal_shutdown,
	clear                          = metal_clear,
	present                        = metal_present,
	draw                           = metal_draw,
	resize_swapchain               = metal_resize_swapchain,
	get_swapchain_width            = metal_get_swapchain_width,
	get_swapchain_height           = metal_get_swapchain_height,
	depth_start                    = metal_depth_start,
	depth_increment_sign           = metal_depth_increment_sign,
	set_internal_state             = metal_set_internal_state,
	create_texture                 = metal_create_texture,
	load_texture                   = metal_load_texture,
	update_texture                 = metal_update_texture,
	destroy_texture                = metal_destroy_texture,
	texture_needs_vertical_flip    = metal_texture_needs_vertical_flip,
	create_render_texture          = metal_create_render_texture,
	destroy_render_target          = metal_destroy_render_target,
	set_texture_filter             = metal_set_texture_filter,
	load_shader                    = metal_load_shader,
	destroy_shader                 = metal_destroy_shader,
	default_shader_vertex_source   = metal_default_shader_vertex_source,
	default_shader_fragment_source = metal_default_shader_fragment_source,
}

import "base:runtime"
import "core:slice"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import hm "handle_map"
import "log"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "vendor:glfw"

Metal_State :: struct {
	allocator:            runtime.Allocator,
	device:               ^MTL.Device,
	command_queue:        ^MTL.CommandQueue,
	layer:                ^CA.MetalLayer,
	width:                int,
	height:               int,
	depth_texture:        ^MTL.Texture,
	vertex_buffer:        ^MTL.Buffer,
	vertex_buffer_offset: int, // Track offset within vertex buffer for each frame
	shaders:              hm.Handle_Map(Metal_Shader, Shader_Handle, 1024 * 10),
	textures:             hm.Handle_Map(Metal_Texture, Texture_Handle, 1024 * 10),
	render_targets:       hm.Handle_Map(Metal_Render_Target, Render_Target_Handle, 128),
	current_drawable:     ^CA.MetalDrawable,
	current_pass:         ^MTL.RenderPassDescriptor,
	current_encoder:      ^MTL.RenderCommandEncoder,
	current_cmd_buffer:   ^MTL.CommandBuffer,
	default_sampler:      ^MTL.SamplerState,
	depth_stencil_state:  ^MTL.DepthStencilState,
}

Metal_Shader :: struct {
	handle:         Shader_Handle,
	pipeline_state: ^MTL.RenderPipelineState,
	vertex_func:    ^MTL.Function,
	fragment_func:  ^MTL.Function,
}

Metal_Texture :: struct {
	handle:              Texture_Handle,
	texture:             ^MTL.Texture,
	format:              Pixel_Format,
	needs_vertical_flip: bool,
	sampler:             ^MTL.SamplerState,
}

Metal_Render_Target :: struct {
	handle:        Render_Target_Handle,
	depth_texture: ^MTL.Texture,
	width:         int,
	height:        int,
}

s: ^Metal_State

metal_state_size :: proc() -> int {
	return size_of(Metal_State)
}

metal_init :: proc(
	state: rawptr,
	window_handle: Window_Handle,
	swapchain_width, swapchain_height: int,
	allocator := context.allocator,
) {
	s = (^Metal_State)(state)
	s.allocator = allocator
	s.width = swapchain_width
	s.height = swapchain_height

	// Create Metal device
	s.device = MTL.CreateSystemDefaultDevice()
	if s.device == nil {
		log.error("Failed to create Metal device")
		return
	}

	// Create command queue
	s.command_queue = s.device->newCommandQueue()
	if s.command_queue == nil {
		log.error("Failed to create Metal command queue")
		return
	}

	// Get native window and view from GLFW
	glfw_window := glfw.WindowHandle(window_handle)
	native_window := glfw.GetCocoaWindow(glfw_window)

	// Create Metal layer
	s.layer = CA.MetalLayer.layer()
	s.layer->setDevice(s.device)
	s.layer->setPixelFormat(.BGRA8Unorm)
	s.layer->setFramebufferOnly(false)

	// Attach layer to window's content view
	content_view := native_window->contentView()
	content_view->setWantsLayer(true)
	content_view->setLayer(s.layer)

	// Set layer frame to match content view bounds
	s.layer->setFrame(content_view->bounds())

	// Set drawable size from framebuffer (handles retina scaling)
	fb_width, fb_height := glfw.GetFramebufferSize(glfw_window)
	s.layer->setDrawableSize(NS.Size{NS.Float(fb_width), NS.Float(fb_height)})
	s.width = int(fb_width)
	s.height = int(fb_height)

	// Create depth texture
	create_depth_texture(s.width, s.height)

	// Create vertex buffer (use default/shared storage)
	s.vertex_buffer = s.device->newBufferWithLength(
		VERTEX_BUFFER_MAX,
		MTL.ResourceStorageModeShared,
	)

	// Create default sampler
	sampler_desc := MTL.SamplerDescriptor.alloc()->init()
	sampler_desc->setMinFilter(.Nearest)
	sampler_desc->setMagFilter(.Nearest)
	sampler_desc->setSAddressMode(.ClampToEdge)
	sampler_desc->setTAddressMode(.ClampToEdge)
	s.default_sampler = s.device->newSamplerState(sampler_desc)
	sampler_desc->release()

	// Create depth stencil state
	depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
	depth_desc->setDepthCompareFunction(.LessEqual)
	depth_desc->setDepthWriteEnabled(true)
	s.depth_stencil_state = s.device->newDepthStencilState(depth_desc)
	depth_desc->release()
}

create_depth_texture :: proc(width, height: int) {
	if s.depth_texture != nil {
		s.depth_texture->release()
	}

	depth_desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		.Depth32Float,
		NS.UInteger(width),
		NS.UInteger(height),
		false,
	)
	depth_desc->setUsage({.RenderTarget})
	depth_desc->setStorageMode(.Private)
	s.depth_texture = s.device->newTextureWithDescriptor(depth_desc)
}

metal_shutdown :: proc() {
	if s.depth_texture != nil {
		s.depth_texture->release()
	}
	if s.vertex_buffer != nil {
		s.vertex_buffer->release()
	}
	if s.default_sampler != nil {
		s.default_sampler->release()
	}
	if s.depth_stencil_state != nil {
		s.depth_stencil_state->release()
	}
	if s.layer != nil {
		s.layer->release()
	}
	if s.command_queue != nil {
		s.command_queue->release()
	}
	if s.device != nil {
		s.device->release()
	}
}

metal_clear :: proc(render_target: Render_Target_Handle, color: Color) {
	// Reset vertex buffer offset at start of frame
	s.vertex_buffer_offset = 0

	// Get drawable for this frame if we haven't already
	if s.current_drawable == nil {
		s.current_drawable = s.layer->nextDrawable()
		if s.current_drawable == nil {
			return
		}
	}

	// Create render pass descriptor
	s.current_pass = MTL.RenderPassDescriptor.renderPassDescriptor()

	color_attachment := s.current_pass->colorAttachments()->object(0)

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		// Render to texture
		tex := hm.get(&s.textures, Texture_Handle(render_target))
		if tex != nil {
			color_attachment->setTexture(tex.texture)
		}
		color_attachment->setLoadAction(.Clear)
		color_attachment->setStoreAction(.Store)

		depth_attachment := s.current_pass->depthAttachment()
		depth_attachment->setTexture(rt.depth_texture)
		depth_attachment->setLoadAction(.Clear)
		depth_attachment->setStoreAction(.DontCare)
		depth_attachment->setClearDepth(1.0)
	} else {
		// Render to screen
		color_attachment->setTexture(s.current_drawable->texture())
		color_attachment->setLoadAction(.Clear)
		color_attachment->setStoreAction(.Store)

		depth_attachment := s.current_pass->depthAttachment()
		depth_attachment->setTexture(s.depth_texture)
		depth_attachment->setLoadAction(.Clear)
		depth_attachment->setStoreAction(.DontCare)
		depth_attachment->setClearDepth(1.0)
	}

	// Set clear color
	color_attachment->setClearColor(
		MTL.ClearColor {
			f64(color[0]) / 255.0,
			f64(color[1]) / 255.0,
			f64(color[2]) / 255.0,
			f64(color[3]) / 255.0,
		},
	)

	// Create command buffer and encoder
	s.current_cmd_buffer = s.command_queue->commandBuffer()
	s.current_encoder = s.current_cmd_buffer->renderCommandEncoderWithDescriptor(s.current_pass)
}

metal_present :: proc() {
	if s.current_encoder != nil {
		s.current_encoder->endEncoding()
		s.current_encoder = nil
	}

	if s.current_cmd_buffer != nil && s.current_drawable != nil {
		s.current_cmd_buffer->presentDrawable(s.current_drawable)
		s.current_cmd_buffer->commit()
		s.current_cmd_buffer = nil
	}

	if s.current_pass != nil {
		s.current_pass->release()
		s.current_pass = nil
	}

	s.current_drawable = nil
}

metal_draw :: proc(
	shd: Shader,
	render_target: Render_Target_Handle,
	bound_textures: []Texture_Handle,
	scissor: Maybe(Rect),
	blend_mode: Blend_Mode,
	vertex_buffer: []u8,
) {
	if len(vertex_buffer) == 0 || s.current_encoder == nil {
		return
	}

	mtl_shd := hm.get(&s.shaders, shd.handle)
	if mtl_shd == nil {
		log.error("Invalid shader handle")
		return
	}

	// Copy vertex data at current offset
	vb_contents := s.vertex_buffer->contents()
	copy(vb_contents[s.vertex_buffer_offset:], vertex_buffer)
	current_offset := s.vertex_buffer_offset
	s.vertex_buffer_offset += len(vertex_buffer)

	// Set pipeline state
	s.current_encoder->setRenderPipelineState(mtl_shd.pipeline_state)

	// Set depth stencil state
	s.current_encoder->setDepthStencilState(s.depth_stencil_state)

	// Set viewport
	viewport := MTL.Viewport {
		originX = 0,
		originY = 0,
		width   = f64(s.width),
		height  = f64(s.height),
		znear   = 0.0,
		zfar    = 1.0,
	}
	s.current_encoder->setViewport(viewport)

	// Set vertex buffer with current offset
	s.current_encoder->setVertexBuffer(s.vertex_buffer, NS.UInteger(current_offset), 0)

	// Set uniforms (MVP matrix is in constants_data)
	if len(shd.constants_data) > 0 {
		s.current_encoder->setVertexBytes(shd.constants_data, 1)
	}

	// Bind textures
	for tex_handle, i in bound_textures {
		if tex := hm.get(&s.textures, tex_handle); tex != nil {
			if tex.texture != nil {
				s.current_encoder->setFragmentTexture(tex.texture, NS.UInteger(i))
				sampler := tex.sampler if tex.sampler != nil else s.default_sampler
				s.current_encoder->setFragmentSamplerState(sampler, NS.UInteger(i))
			}
		}
	}

	// Set scissor rect
	if sci, ok := scissor.?; ok {
		scissor_rect := MTL.ScissorRect {
			x      = NS.Integer(max(0, int(sci.x))),
			y      = NS.Integer(max(0, int(sci.y))),
			width  = NS.Integer(sci.w),
			height = NS.Integer(sci.h),
		}
		s.current_encoder->setScissorRect(scissor_rect)
	} else {
		s.current_encoder->setScissorRect({0, 0, NS.Integer(s.width), NS.Integer(s.height)})
	}

	// Draw
	vertex_count := len(vertex_buffer) / shd.vertex_size
	s.current_encoder->drawPrimitives(.Triangle, 0, NS.UInteger(vertex_count))
}

metal_resize_swapchain :: proc(width, height: int) {
	s.width = width
	s.height = height
	s.layer->setDrawableSize(NS.Size{NS.Float(width), NS.Float(height)})
	create_depth_texture(width, height)
}

metal_get_swapchain_width :: proc() -> int {
	return s.width
}

metal_get_swapchain_height :: proc() -> int {
	return s.height
}

metal_depth_start :: proc() -> f32 {
	return 0.0
}

metal_depth_increment_sign :: proc() -> int {
	return 1
}

metal_set_internal_state :: proc(state: rawptr) {
	s = (^Metal_State)(state)
}

metal_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	mtl_format := metal_translate_pixel_format(format)

	// Use explicit descriptor setup like working Metal examples
	desc := MTL.TextureDescriptor.alloc()->init()
	defer desc->release()

	desc->setTextureType(.Type2D)
	desc->setWidth(NS.UInteger(width))
	desc->setHeight(NS.UInteger(height))
	desc->setPixelFormat(mtl_format)
	desc->setStorageMode(.Managed)
	desc->setUsage({.ShaderRead})

	texture := s.device->newTextureWithDescriptor(desc)

	mtl_tex := Metal_Texture {
		texture = texture,
		format  = format,
	}

	return hm.add(&s.textures, mtl_tex)
}

metal_load_texture :: proc(
	data: []u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> Texture_Handle {
	handle := metal_create_texture(width, height, format)

	if tex := hm.get(&s.textures, handle); tex != nil {
		bytes_per_pixel := pixel_format_size(format)
		bytes_per_row := width * bytes_per_pixel
		data_size := len(data)

		// Clone the data to ensure it persists during the replaceRegion call
		// (the source data may be in frame_allocator which could be freed)
		cloned_data := make([]u8, data_size, s.allocator)
		copy(cloned_data, data)
		defer delete(cloned_data, s.allocator)

		region := MTL.Region {
			origin = {0, 0, 0},
			size   = {NS.Integer(width), NS.Integer(height), 1},
		}

		tex.texture->replaceRegion(region, 0, raw_data(cloned_data), NS.UInteger(bytes_per_row))
	}

	return handle
}

metal_update_texture :: proc(handle: Texture_Handle, data: []u8, rect: Rect) -> bool {
	tex := hm.get(&s.textures, handle)
	if tex == nil {
		return false
	}

	bytes_per_pixel := pixel_format_size(tex.format)
	bytes_per_row := int(rect.w) * bytes_per_pixel

	region := MTL.Region {
		origin = {NS.Integer(rect.x), NS.Integer(rect.y), 0},
		size   = {NS.Integer(rect.w), NS.Integer(rect.h), 1},
	}

	tex.texture->replaceRegion(region, 0, raw_data(data), NS.UInteger(bytes_per_row))
	return true
}

metal_destroy_texture :: proc(handle: Texture_Handle) {
	if tex := hm.get(&s.textures, handle); tex != nil {
		if tex.texture != nil {
			tex.texture->release()
		}
		if tex.sampler != nil {
			tex.sampler->release()
		}
		hm.remove(&s.textures, handle)
	}
}

metal_texture_needs_vertical_flip :: proc(handle: Texture_Handle) -> bool {
	if tex := hm.get(&s.textures, handle); tex != nil {
		return tex.needs_vertical_flip
	}
	return false
}

metal_create_render_texture :: proc(
	width: int,
	height: int,
) -> (
	Texture_Handle,
	Render_Target_Handle,
) {
	// Create color texture
	color_desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		.BGRA8Unorm,
		NS.UInteger(width),
		NS.UInteger(height),
		false,
	)
	color_desc->setUsage({.ShaderRead, .RenderTarget})
	color_desc->setStorageMode(.Private)

	color_texture := s.device->newTextureWithDescriptor(color_desc)

	mtl_tex := Metal_Texture {
		texture             = color_texture,
		format              = .RGBA_8_Norm,
		needs_vertical_flip = true,
	}

	tex_handle := hm.add(&s.textures, mtl_tex)

	// Create depth texture for render target
	depth_desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		.Depth32Float,
		NS.UInteger(width),
		NS.UInteger(height),
		false,
	)
	depth_desc->setUsage({.RenderTarget})
	depth_desc->setStorageMode(.Private)

	depth_texture := s.device->newTextureWithDescriptor(depth_desc)

	rt := Metal_Render_Target {
		depth_texture = depth_texture,
		width         = width,
		height        = height,
	}

	rt_handle := hm.add(&s.render_targets, rt)

	return tex_handle, rt_handle
}

metal_destroy_render_target :: proc(handle: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, handle); rt != nil {
		if rt.depth_texture != nil {
			rt.depth_texture->release()
		}
		hm.remove(&s.render_targets, handle)
	}
}

metal_set_texture_filter :: proc(
	handle: Texture_Handle,
	scale_down_filter: Texture_Filter,
	scale_up_filter: Texture_Filter,
	mip_filter: Texture_Filter,
) {
	tex := hm.get(&s.textures, handle)
	if tex == nil {
		return
	}

	// Release old sampler if exists
	if tex.sampler != nil {
		tex.sampler->release()
	}

	sampler_desc := MTL.SamplerDescriptor.alloc()->init()
	sampler_desc->setMinFilter(scale_down_filter == .Linear ? .Linear : .Nearest)
	sampler_desc->setMagFilter(scale_up_filter == .Linear ? .Linear : .Nearest)
	sampler_desc->setMipFilter(mip_filter == .Linear ? .Linear : .Nearest)
	sampler_desc->setSAddressMode(.ClampToEdge)
	sampler_desc->setTAddressMode(.ClampToEdge)

	tex.sampler = s.device->newSamplerState(sampler_desc)
	sampler_desc->release()
}

metal_load_shader :: proc(
	vs_source: []byte,
	fs_source: []byte,
	desc_allocator := frame_allocator,
	layout_formats: []Pixel_Format = {},
) -> (
	handle: Shader_Handle,
	desc: Shader_Desc,
) {
	// For Metal, vs_source and fs_source should both contain the same Metal shader library source
	// (Metal uses a single source file with both vertex and fragment functions)

	shader_source := NS.String.alloc()->initWithOdinString(string(vs_source))
	defer shader_source->release()

	library, err := s.device->newLibraryWithSource(shader_source, nil)
	if library == nil {
		if err != nil {
			log.error("Failed to compile Metal shader:", err->localizedDescription()->odinString())
		}
		return {}, {}
	}
	defer library->release()

	vertex_func := library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_func := library->newFunctionWithName(NS.AT("fragment_main"))

	if vertex_func == nil || fragment_func == nil {
		log.error("Failed to find vertex_main or fragment_main in Metal shader")
		if vertex_func != nil do vertex_func->release()
		if fragment_func != nil do fragment_func->release()
		return {}, {}
	}

	// Create pipeline descriptor
	pipeline_desc := MTL.RenderPipelineDescriptor.alloc()->init()
	pipeline_desc->setVertexFunction(vertex_func)
	pipeline_desc->setFragmentFunction(fragment_func)
	pipeline_desc->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm)
	pipeline_desc->setDepthAttachmentPixelFormat(.Depth32Float)

	// Set up blending
	color_attachment := pipeline_desc->colorAttachments()->object(0)
	color_attachment->setBlendingEnabled(true)
	color_attachment->setSourceRGBBlendFactor(.SourceAlpha)
	color_attachment->setDestinationRGBBlendFactor(.OneMinusSourceAlpha)
	color_attachment->setRgbBlendOperation(.Add)
	color_attachment->setSourceAlphaBlendFactor(.SourceAlpha)
	color_attachment->setDestinationAlphaBlendFactor(.OneMinusSourceAlpha)
	color_attachment->setAlphaBlendOperation(.Add)

	// Create vertex descriptor
	vertex_desc := MTL.VertexDescriptor.vertexDescriptor()

	// Position (float3)
	vertex_desc->attributes()->object(0)->setFormat(.Float3)
	vertex_desc->attributes()->object(0)->setOffset(0)
	vertex_desc->attributes()->object(0)->setBufferIndex(0)

	// TexCoord (float2)
	vertex_desc->attributes()->object(1)->setFormat(.Float2)
	vertex_desc->attributes()->object(1)->setOffset(12)
	vertex_desc->attributes()->object(1)->setBufferIndex(0)

	// Color (float4 from normalized u8)
	vertex_desc->attributes()->object(2)->setFormat(.UChar4Normalized)
	vertex_desc->attributes()->object(2)->setOffset(20)
	vertex_desc->attributes()->object(2)->setBufferIndex(0)

	// Vertex buffer layout: position(12) + texcoord(8) + color(4) = 24 bytes
	vertex_desc->layouts()->object(0)->setStride(24)
	vertex_desc->layouts()->object(0)->setStepFunction(.PerVertex)

	pipeline_desc->setVertexDescriptor(vertex_desc)

	// Create pipeline state
	pipeline_state, pso_err := s.device->newRenderPipelineState(pipeline_desc)
	pipeline_desc->release()

	if pipeline_state == nil {
		if pso_err != nil {
			log.error(
				"Failed to create pipeline state:",
				pso_err->localizedDescription()->odinString(),
			)
		}
		vertex_func->release()
		fragment_func->release()
		return {}, {}
	}

	mtl_shd := Metal_Shader {
		pipeline_state = pipeline_state,
		vertex_func    = vertex_func,
		fragment_func  = fragment_func,
	}

	handle = hm.add(&s.shaders, mtl_shd)

	// Build shader description
	desc.inputs = make([]Shader_Input, 3, desc_allocator)
	desc.inputs[0] = {
		name     = "position",
		register = 0,
		type     = .Vec3,
		format   = .RGB_32_Float,
	}
	desc.inputs[1] = {
		name     = "texcoord",
		register = 1,
		type     = .Vec2,
		format   = .RG_32_Float,
	}
	desc.inputs[2] = {
		name     = "color",
		register = 2,
		type     = .Vec4,
		format   = .RGBA_8_Norm,
	}

	desc.constants = make([]Shader_Constant_Desc, 1, desc_allocator)
	desc.constants[0] = {
		name = "mvp",
		size = 64,
	}

	desc.texture_bindpoints = make([]Shader_Texture_Bindpoint_Desc, 1, desc_allocator)
	desc.texture_bindpoints[0] = {
		name = "tex",
	}

	return handle, desc
}

metal_destroy_shader :: proc(handle: Shader_Handle) {
	if shd := hm.get(&s.shaders, handle); shd != nil {
		if shd.pipeline_state != nil {
			shd.pipeline_state->release()
		}
		if shd.vertex_func != nil {
			shd.vertex_func->release()
		}
		if shd.fragment_func != nil {
			shd.fragment_func->release()
		}
		hm.remove(&s.shaders, handle)
	}
}

metal_translate_pixel_format :: proc(format: Pixel_Format) -> MTL.PixelFormat {
	switch format {
	case .RGBA_32_Float:
		return .RGBA32Float
	case .RGB_32_Float:
		return .Invalid // Metal doesn't have RGB32Float, would need to use RGBA
	case .RG_32_Float:
		return .RG32Float
	case .R_32_Float:
		return .R32Float
	case .RGBA_8_Norm:
		return .RGBA8Unorm
	case .RG_8_Norm:
		return .RG8Unorm
	case .R_8_Norm:
		return .R8Unorm
	case .R_8_UInt:
		return .R8Uint
	case .Unknown:
		return .Invalid
	}
	return .Invalid
}

metal_default_shader_vertex_source :: proc() -> []byte {
	return #load("render_backend_metal_default_shader.metal")
}

metal_default_shader_fragment_source :: proc() -> []byte {
	// Metal uses a single source file for both vertex and fragment
	return #load("render_backend_metal_default_shader.metal")
}
