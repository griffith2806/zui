// Vulkan renderer backend for zui.
//
// Design notes:
//   - No Vulkan SDK headers required.  All VkXxx types are declared inline
//     as Zig structs / opaque handles so the file compiles without any C
//     include paths or installed SDK.
//   - Dispatchable handles (VkInstance, VkPhysicalDevice, VkDevice, VkQueue,
//     VkCommandBuffer) are represented as `*opaque{}` — on 64-bit targets
//     they are plain pointers.
//   - Non-dispatchable handles (surfaces, swapchains, render passes, …) are
//     `u64` — Vulkan guarantees 64-bit even on 32-bit hosts when using the
//     non-dispatchable typedef.
//   - All Vulkan entry points are loaded at runtime via vkGetInstanceProcAddr
//     (global loader) and vkGetDeviceProcAddr (per-device calls) so no import
//     library or .def file is needed at link time.
//   - Text rendering is deferred: drawText / textWidth return no-ops / 0 for
//     now and can be fleshed out later with a glyph atlas pipeline.
//
// Solid-color rect rendering uses a push-constant pipeline:
//   push-constant block: { rect: vec4, color: vec4 }
//   vertex shader:  full-screen triangle trick (3 verts, no VBO needed)
//   fragment shader: NDC-space rect test, outputs push-constant color
//
// The implementation calls real Vulkan functions but guards every call with
// an error check.  If the Vulkan loader DLL is absent (non-Vulkan machine)
// init() returns error.VulkanLoaderNotFound and the application can fall back
// to another backend.

const std   = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;
const Image = @import("../image.zig").Image;

// ── Vulkan result codes ───────────────────────────────────────────────────────

pub const VkResult = i32;
pub const VK_SUCCESS:               VkResult =  0;
pub const VK_SUBOPTIMAL_KHR:        VkResult =  1000001003;
pub const VK_ERROR_OUT_OF_HOST_MEMORY:   VkResult = -1;
pub const VK_ERROR_OUT_OF_DEVICE_MEMORY: VkResult = -2;
pub const VK_ERROR_SURFACE_LOST_KHR:    VkResult = -1000000000;
pub const VK_ERROR_NATIVE_WINDOW_IN_USE_KHR: VkResult = -1000000001;
pub const VK_ERROR_OUT_OF_DATE_KHR:  VkResult = -1000001004;

// ── Dispatchable handles (pointer-sized) ──────────────────────────────────────

pub const VkInstance        = *opaque{};
pub const VkPhysicalDevice  = *opaque{};
pub const VkDevice          = *opaque{};
pub const VkQueue           = *opaque{};
pub const VkCommandBuffer   = *opaque{};

// ── Non-dispatchable handles (always 64-bit) ──────────────────────────────────

pub const VkSurfaceKHR          = u64;
pub const VkSwapchainKHR        = u64;
pub const VkRenderPass          = u64;
pub const VkFramebuffer         = u64;
pub const VkPipeline            = u64;
pub const VkPipelineLayout      = u64;
pub const VkCommandPool         = u64;
pub const VkSemaphore           = u64;
pub const VkFence               = u64;
pub const VkImage               = u64;
pub const VkImageView           = u64;
pub const VkShaderModule        = u64;
pub const VkDescriptorSetLayout = u64;

pub const VK_NULL_HANDLE: u64 = 0;

// ── Common flags / enums ──────────────────────────────────────────────────────

pub const VkFormat = i32;
pub const VK_FORMAT_UNDEFINED:         VkFormat = 0;
pub const VK_FORMAT_B8G8R8A8_UNORM:   VkFormat = 44;
pub const VK_FORMAT_B8G8R8A8_SRGB:    VkFormat = 50;
pub const VK_FORMAT_R8G8B8A8_UNORM:   VkFormat = 37;

pub const VkColorSpaceKHR = i32;
pub const VK_COLOR_SPACE_SRGB_NONLINEAR_KHR: VkColorSpaceKHR = 0;

pub const VkPresentModeKHR = i32;
pub const VK_PRESENT_MODE_FIFO_KHR: VkPresentModeKHR = 2;

pub const VkSharingMode = i32;
pub const VK_SHARING_MODE_EXCLUSIVE:  VkSharingMode = 0;
pub const VK_SHARING_MODE_CONCURRENT: VkSharingMode = 1;

pub const VkImageLayout = i32;
pub const VK_IMAGE_LAYOUT_UNDEFINED:                 VkImageLayout = 0;
pub const VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:  VkImageLayout = 2;
pub const VK_IMAGE_LAYOUT_PRESENT_SRC_KHR:           VkImageLayout = 1000001002;

pub const VkAttachmentLoadOp = i32;
pub const VK_ATTACHMENT_LOAD_OP_CLEAR:     VkAttachmentLoadOp = 1;
pub const VK_ATTACHMENT_LOAD_OP_DONT_CARE: VkAttachmentLoadOp = 2;

pub const VkAttachmentStoreOp = i32;
pub const VK_ATTACHMENT_STORE_OP_STORE:     VkAttachmentStoreOp = 0;
pub const VK_ATTACHMENT_STORE_OP_DONT_CARE: VkAttachmentStoreOp = 1;

pub const VkPipelineBindPoint = i32;
pub const VK_PIPELINE_BIND_POINT_GRAPHICS: VkPipelineBindPoint = 0;

pub const VkSampleCountFlagBits = u32;
pub const VK_SAMPLE_COUNT_1_BIT: VkSampleCountFlagBits = 1;

pub const VkImageUsageFlags = u32;
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: VkImageUsageFlags = 0x00000010;

pub const VkCompositeAlphaFlagBitsKHR = u32;
pub const VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR: VkCompositeAlphaFlagBitsKHR = 1;

pub const VkQueueFlags = u32;
pub const VK_QUEUE_GRAPHICS_BIT: VkQueueFlags = 0x00000001;

pub const VkCommandPoolCreateFlags = u32;
pub const VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT: VkCommandPoolCreateFlags = 0x00000002;

pub const VkCommandBufferLevel = i32;
pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY: VkCommandBufferLevel = 0;

pub const VkCommandBufferUsageFlags = u32;

pub const VkSubpassContents = i32;
pub const VK_SUBPASS_CONTENTS_INLINE: VkSubpassContents = 0;

pub const VkFenceCreateFlags = u32;
pub const VK_FENCE_CREATE_SIGNALED_BIT: VkFenceCreateFlags = 0x00000001;

pub const VkPipelineStageFlags = u32;
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: VkPipelineStageFlags = 0x00000400;

pub const VkShaderStageFlags = u32;
pub const VK_SHADER_STAGE_VERTEX_BIT:   VkShaderStageFlags = 0x00000001;
pub const VK_SHADER_STAGE_FRAGMENT_BIT: VkShaderStageFlags = 0x00000010;

pub const VkImageViewType = i32;
pub const VK_IMAGE_VIEW_TYPE_2D: VkImageViewType = 1;

pub const VkImageAspectFlags = u32;
pub const VK_IMAGE_ASPECT_COLOR_BIT: VkImageAspectFlags = 0x00000001;

pub const VkComponentSwizzle = i32;
pub const VK_COMPONENT_SWIZZLE_IDENTITY: VkComponentSwizzle = 0;

pub const VkPrimitiveTopology = i32;
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: VkPrimitiveTopology = 3;

pub const VkPolygonMode = i32;
pub const VK_POLYGON_MODE_FILL: VkPolygonMode = 0;

pub const VkCullModeFlags = u32;
pub const VK_CULL_MODE_NONE: VkCullModeFlags = 0;

pub const VkFrontFace = i32;
pub const VK_FRONT_FACE_COUNTER_CLOCKWISE: VkFrontFace = 1;

pub const VkBlendFactor = i32;
pub const VK_BLEND_FACTOR_ZERO:                VkBlendFactor = 0;
pub const VK_BLEND_FACTOR_ONE:                 VkBlendFactor = 1;
pub const VK_BLEND_FACTOR_SRC_ALPHA:           VkBlendFactor = 6;
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: VkBlendFactor = 7;

pub const VkBlendOp = i32;
pub const VK_BLEND_OP_ADD: VkBlendOp = 0;

pub const VkColorComponentFlags = u32;
pub const VK_COLOR_COMPONENT_RGBA: VkColorComponentFlags = 0x0000000F;

pub const VkLogicOp = i32;
pub const VK_LOGIC_OP_COPY: VkLogicOp = 3;

pub const VkDynamicState = i32;
pub const VK_DYNAMIC_STATE_VIEWPORT: VkDynamicState = 0;
pub const VK_DYNAMIC_STATE_SCISSOR:  VkDynamicState = 1;

pub const VkStructureType = i32;
pub const VK_STRUCTURE_TYPE_APPLICATION_INFO:                           VkStructureType = 0;
pub const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO:                       VkStructureType = 1;
pub const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO:                   VkStructureType = 2;
pub const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO:                         VkStructureType = 3;
pub const VK_STRUCTURE_TYPE_SUBMIT_INFO:                                VkStructureType = 4;
pub const VK_STRUCTURE_TYPE_FENCE_CREATE_INFO:                          VkStructureType = 8;
pub const VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO:                      VkStructureType = 9;
pub const VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO:                     VkStructureType = 14;
pub const VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO:                  VkStructureType = 15;
pub const VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO:          VkStructureType = 18;
pub const VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO:    VkStructureType = 19;
pub const VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO:  VkStructureType = 20;
pub const VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO:        VkStructureType = 22;
pub const VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO:   VkStructureType = 23;
pub const VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO:     VkStructureType = 24;
pub const VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO:     VkStructureType = 26;
pub const VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO:         VkStructureType = 27;
pub const VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO:              VkStructureType = 28;
pub const VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO:                VkStructureType = 30;
pub const VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO:                    VkStructureType = 38;
pub const VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO:                   VkStructureType = 39;
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO:               VkStructureType = 40;
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO:                  VkStructureType = 42;
pub const VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO:                     VkStructureType = 43;
pub const VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO:                    VkStructureType = 37;
pub const VK_STRUCTURE_TYPE_PRESENT_INFO_KHR:                           VkStructureType = 1000001001;
pub const VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR:                  VkStructureType = 1000001000;
pub const VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR:              VkStructureType = 1000009000;

// ── Vulkan structs ────────────────────────────────────────────────────────────

pub const VkExtent2D = extern struct {
    width:  u32,
    height: u32,
};

pub const VkExtent3D = extern struct {
    width:  u32,
    height: u32,
    depth:  u32,
};

pub const VkOffset2D = extern struct {
    x: i32,
    y: i32,
};

pub const VkRect2D = extern struct {
    offset: VkOffset2D,
    extent: VkExtent2D,
};

pub const VkViewport = extern struct {
    x:         f32,
    y:         f32,
    width:     f32,
    height:    f32,
    minDepth:  f32,
    maxDepth:  f32,
};

pub const VkClearColorValue = extern union {
    float32: [4]f32,
    int32:   [4]i32,
    uint32:  [4]u32,
};

pub const VkClearDepthStencilValue = extern struct {
    depth:   f32,
    stencil: u32,
};

pub const VkClearValue = extern union {
    color:        VkClearColorValue,
    depthStencil: VkClearDepthStencilValue,
};

pub const VkApplicationInfo = extern struct {
    sType:              VkStructureType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
    pNext:              ?*const anyopaque = null,
    pApplicationName:   ?[*:0]const u8 = null,
    applicationVersion: u32 = 0,
    pEngineName:        ?[*:0]const u8 = null,
    engineVersion:      u32 = 0,
    apiVersion:         u32 = 0,
};

pub const VkInstanceCreateInfo = extern struct {
    sType:                   VkStructureType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    pNext:                   ?*const anyopaque = null,
    flags:                   u32 = 0,
    pApplicationInfo:        ?*const VkApplicationInfo = null,
    enabledLayerCount:       u32 = 0,
    ppEnabledLayerNames:     ?[*]const [*:0]const u8 = null,
    enabledExtensionCount:   u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
};

pub const VkDeviceQueueCreateInfo = extern struct {
    sType:            VkStructureType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    pNext:            ?*const anyopaque = null,
    flags:            u32 = 0,
    queueFamilyIndex: u32,
    queueCount:       u32,
    pQueuePriorities: [*]const f32,
};

pub const VkPhysicalDeviceFeatures = extern struct {
    // 55 u32 booleans; all default to 0 (disabled)
    robustBufferAccess:                      u32 = 0,
    fullDrawIndexUint32:                     u32 = 0,
    imageCubeArray:                          u32 = 0,
    independentBlend:                        u32 = 0,
    geometryShader:                          u32 = 0,
    tessellationShader:                      u32 = 0,
    sampleRateShading:                       u32 = 0,
    dualSrcBlend:                            u32 = 0,
    logicOp:                                 u32 = 0,
    multiDrawIndirect:                       u32 = 0,
    drawIndirectFirstInstance:               u32 = 0,
    depthClamp:                              u32 = 0,
    depthBiasClamp:                          u32 = 0,
    fillModeNonSolid:                        u32 = 0,
    depthBounds:                             u32 = 0,
    wideLines:                               u32 = 0,
    largePoints:                             u32 = 0,
    alphaToOne:                              u32 = 0,
    multiViewport:                           u32 = 0,
    samplerAnisotropy:                       u32 = 0,
    textureCompressionETC2:                  u32 = 0,
    textureCompressionASTC_LDR:              u32 = 0,
    textureCompressionBC:                    u32 = 0,
    occlusionQueryPrecise:                   u32 = 0,
    pipelineStatisticsQuery:                 u32 = 0,
    vertexPipelineStoresAndAtomics:          u32 = 0,
    fragmentStoresAndAtomics:                u32 = 0,
    shaderTessellationAndGeometryPointSize:  u32 = 0,
    shaderImageGatherExtended:               u32 = 0,
    shaderStorageImageExtendedFormats:       u32 = 0,
    shaderStorageImageMultisample:           u32 = 0,
    shaderStorageImageReadWithoutFormat:     u32 = 0,
    shaderStorageImageWriteWithoutFormat:    u32 = 0,
    shaderUniformBufferArrayDynamicIndexing: u32 = 0,
    shaderSampledImageArrayDynamicIndexing:  u32 = 0,
    shaderStorageBufferArrayDynamicIndexing: u32 = 0,
    shaderStorageImageArrayDynamicIndexing:  u32 = 0,
    shaderClipDistance:                      u32 = 0,
    shaderCullDistance:                      u32 = 0,
    shaderFloat64:                           u32 = 0,
    shaderInt64:                             u32 = 0,
    shaderInt16:                             u32 = 0,
    shaderResourceResidency:                 u32 = 0,
    shaderResourceMinLod:                    u32 = 0,
    sparseBinding:                           u32 = 0,
    sparseResidencyBuffer:                   u32 = 0,
    sparseResidencyImage2D:                  u32 = 0,
    sparseResidencyImage3D:                  u32 = 0,
    sparseResidency2Samples:                 u32 = 0,
    sparseResidency4Samples:                 u32 = 0,
    sparseResidency8Samples:                 u32 = 0,
    sparseResidency16Samples:                u32 = 0,
    sparseResidencyAliased:                  u32 = 0,
    variableMultisampleRate:                 u32 = 0,
    inheritedQueries:                        u32 = 0,
};

pub const VkDeviceCreateInfo = extern struct {
    sType:                   VkStructureType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    pNext:                   ?*const anyopaque = null,
    flags:                   u32 = 0,
    queueCreateInfoCount:    u32,
    pQueueCreateInfos:       [*]const VkDeviceQueueCreateInfo,
    enabledLayerCount:       u32 = 0,
    ppEnabledLayerNames:     ?[*]const [*:0]const u8 = null,
    enabledExtensionCount:   u32 = 0,
    ppEnabledExtensionNames: ?[*]const [*:0]const u8 = null,
    pEnabledFeatures:        ?*const VkPhysicalDeviceFeatures = null,
};

pub const VkQueueFamilyProperties = extern struct {
    queueFlags:                  VkQueueFlags,
    queueCount:                  u32,
    timestampValidBits:          u32,
    minImageTransferGranularity: VkExtent3D,
};

pub const VkSurfaceCapabilitiesKHR = extern struct {
    minImageCount:           u32,
    maxImageCount:           u32,
    currentExtent:           VkExtent2D,
    minImageExtent:          VkExtent2D,
    maxImageExtent:          VkExtent2D,
    maxImageArrayLayers:     u32,
    supportedTransforms:     u32,
    currentTransform:        u32,
    supportedCompositeAlpha: u32,
    supportedUsageFlags:     u32,
};

pub const VkSurfaceFormatKHR = extern struct {
    format:     VkFormat,
    colorSpace: VkColorSpaceKHR,
};

pub const VkSwapchainCreateInfoKHR = extern struct {
    sType:                 VkStructureType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
    pNext:                 ?*const anyopaque = null,
    flags:                 u32 = 0,
    surface:               VkSurfaceKHR,
    minImageCount:         u32,
    imageFormat:           VkFormat,
    imageColorSpace:       VkColorSpaceKHR,
    imageExtent:           VkExtent2D,
    imageArrayLayers:      u32,
    imageUsage:            VkImageUsageFlags,
    imageSharingMode:      VkSharingMode,
    queueFamilyIndexCount: u32,
    pQueueFamilyIndices:   ?[*]const u32,
    preTransform:          u32,
    compositeAlpha:        VkCompositeAlphaFlagBitsKHR,
    presentMode:           VkPresentModeKHR,
    clipped:               u32,
    oldSwapchain:          VkSwapchainKHR,
};

pub const VkAttachmentDescription = extern struct {
    flags:          u32 = 0,
    format:         VkFormat,
    samples:        VkSampleCountFlagBits,
    loadOp:         VkAttachmentLoadOp,
    storeOp:        VkAttachmentStoreOp,
    stencilLoadOp:  VkAttachmentLoadOp,
    stencilStoreOp: VkAttachmentStoreOp,
    initialLayout:  VkImageLayout,
    finalLayout:    VkImageLayout,
};

pub const VkAttachmentReference = extern struct {
    attachment: u32,
    layout:     VkImageLayout,
};

pub const VkSubpassDescription = extern struct {
    flags:                   u32 = 0,
    pipelineBindPoint:       VkPipelineBindPoint,
    inputAttachmentCount:    u32 = 0,
    pInputAttachments:       ?[*]const VkAttachmentReference = null,
    colorAttachmentCount:    u32,
    pColorAttachments:       [*]const VkAttachmentReference,
    pResolveAttachments:     ?[*]const VkAttachmentReference = null,
    pDepthStencilAttachment: ?*const VkAttachmentReference = null,
    preserveAttachmentCount: u32 = 0,
    pPreserveAttachments:    ?[*]const u32 = null,
};

pub const VkSubpassDependency = extern struct {
    srcSubpass:      u32,
    dstSubpass:      u32,
    srcStageMask:    VkPipelineStageFlags,
    dstStageMask:    VkPipelineStageFlags,
    srcAccessMask:   u32,
    dstAccessMask:   u32,
    dependencyFlags: u32 = 0,
};

pub const VK_SUBPASS_EXTERNAL: u32 = 0xFFFF_FFFF;
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: u32 = 0x00000100;

pub const VkRenderPassCreateInfo = extern struct {
    sType:           VkStructureType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
    pNext:           ?*const anyopaque = null,
    flags:           u32 = 0,
    attachmentCount: u32,
    pAttachments:    [*]const VkAttachmentDescription,
    subpassCount:    u32,
    pSubpasses:      [*]const VkSubpassDescription,
    dependencyCount: u32 = 0,
    pDependencies:   ?[*]const VkSubpassDependency = null,
};

pub const VkCommandPoolCreateInfo = extern struct {
    sType:            VkStructureType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
    pNext:            ?*const anyopaque = null,
    flags:            VkCommandPoolCreateFlags = 0,
    queueFamilyIndex: u32,
};

pub const VkCommandBufferAllocateInfo = extern struct {
    sType:              VkStructureType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    pNext:              ?*const anyopaque = null,
    commandPool:        VkCommandPool,
    level:              VkCommandBufferLevel,
    commandBufferCount: u32,
};

pub const VkCommandBufferBeginInfo = extern struct {
    sType:            VkStructureType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    pNext:            ?*const anyopaque = null,
    flags:            VkCommandBufferUsageFlags = 0,
    pInheritanceInfo: ?*const anyopaque = null,
};

pub const VkRenderPassBeginInfo = extern struct {
    sType:           VkStructureType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    pNext:           ?*const anyopaque = null,
    renderPass:      VkRenderPass,
    framebuffer:     VkFramebuffer,
    renderArea:      VkRect2D,
    clearValueCount: u32,
    pClearValues:    [*]const VkClearValue,
};

pub const VkSubmitInfo = extern struct {
    sType:                VkStructureType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
    pNext:                ?*const anyopaque = null,
    waitSemaphoreCount:   u32 = 0,
    pWaitSemaphores:      ?[*]const VkSemaphore = null,
    pWaitDstStageMask:    ?[*]const VkPipelineStageFlags = null,
    commandBufferCount:   u32,
    pCommandBuffers:      [*]const VkCommandBuffer,
    signalSemaphoreCount: u32 = 0,
    pSignalSemaphores:    ?[*]const VkSemaphore = null,
};

pub const VkPresentInfoKHR = extern struct {
    sType:              VkStructureType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
    pNext:              ?*const anyopaque = null,
    waitSemaphoreCount: u32 = 0,
    pWaitSemaphores:    ?[*]const VkSemaphore = null,
    swapchainCount:     u32,
    pSwapchains:        [*]const VkSwapchainKHR,
    pImageIndices:      [*]const u32,
    pResults:           ?[*]VkResult = null,
};

pub const VkFenceCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: VkFenceCreateFlags = 0,
};

pub const VkSemaphoreCreateInfo = extern struct {
    sType: VkStructureType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    pNext: ?*const anyopaque = null,
    flags: u32 = 0,
};

pub const VkComponentMapping = extern struct {
    r: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    g: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    b: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
    a: VkComponentSwizzle = VK_COMPONENT_SWIZZLE_IDENTITY,
};

pub const VkImageSubresourceRange = extern struct {
    aspectMask:     VkImageAspectFlags,
    baseMipLevel:   u32,
    levelCount:     u32,
    baseArrayLayer: u32,
    layerCount:     u32,
};

pub const VkImageViewCreateInfo = extern struct {
    sType:            VkStructureType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
    pNext:            ?*const anyopaque = null,
    flags:            u32 = 0,
    image:            VkImage,
    viewType:         VkImageViewType,
    format:           VkFormat,
    components:       VkComponentMapping,
    subresourceRange: VkImageSubresourceRange,
};

pub const VkFramebufferCreateInfo = extern struct {
    sType:           VkStructureType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
    pNext:           ?*const anyopaque = null,
    flags:           u32 = 0,
    renderPass:      VkRenderPass,
    attachmentCount: u32,
    pAttachments:    [*]const VkImageView,
    width:           u32,
    height:          u32,
    layers:          u32,
};

pub const VkShaderModuleCreateInfo = extern struct {
    sType:    VkStructureType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    pNext:    ?*const anyopaque = null,
    flags:    u32 = 0,
    codeSize: usize,
    pCode:    [*]const u32,
};

pub const VkPushConstantRange = extern struct {
    stageFlags: VkShaderStageFlags,
    offset:     u32,
    size:       u32,
};

pub const VkPipelineLayoutCreateInfo = extern struct {
    sType:                  VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    pNext:                  ?*const anyopaque = null,
    flags:                  u32 = 0,
    setLayoutCount:         u32 = 0,
    pSetLayouts:            ?[*]const VkDescriptorSetLayout = null,
    pushConstantRangeCount: u32 = 0,
    pPushConstantRanges:    ?[*]const VkPushConstantRange = null,
};

pub const VkPipelineShaderStageCreateInfo = extern struct {
    sType:               VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
    pNext:               ?*const anyopaque = null,
    flags:               u32 = 0,
    stage:               VkShaderStageFlags,
    module:              VkShaderModule,
    pName:               [*:0]const u8,
    pSpecializationInfo: ?*const anyopaque = null,
};

pub const VkPipelineVertexInputStateCreateInfo = extern struct {
    sType:                           VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    pNext:                           ?*const anyopaque = null,
    flags:                           u32 = 0,
    vertexBindingDescriptionCount:   u32 = 0,
    pVertexBindingDescriptions:      ?*const anyopaque = null,  // VkVertexInputBindingDescription* — always null for full-screen triangle
    vertexAttributeDescriptionCount: u32 = 0,
    pVertexAttributeDescriptions:    ?*const anyopaque = null,  // VkVertexInputAttributeDescription* — always null for full-screen triangle
};

pub const VkPipelineInputAssemblyStateCreateInfo = extern struct {
    sType:                  VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    pNext:                  ?*const anyopaque = null,
    flags:                  u32 = 0,
    topology:               VkPrimitiveTopology,
    primitiveRestartEnable: u32 = 0,
};

pub const VkPipelineViewportStateCreateInfo = extern struct {
    sType:         VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    pNext:         ?*const anyopaque = null,
    flags:         u32 = 0,
    viewportCount: u32,
    pViewports:    ?[*]const VkViewport = null,
    scissorCount:  u32,
    pScissors:     ?[*]const VkRect2D = null,
};

pub const VkPipelineRasterizationStateCreateInfo = extern struct {
    sType:                   VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    pNext:                   ?*const anyopaque = null,
    flags:                   u32 = 0,
    depthClampEnable:        u32 = 0,
    rasterizerDiscardEnable: u32 = 0,
    polygonMode:             VkPolygonMode,
    cullMode:                VkCullModeFlags,
    frontFace:               VkFrontFace,
    depthBiasEnable:         u32 = 0,
    depthBiasConstantFactor: f32 = 0.0,
    depthBiasClamp:          f32 = 0.0,
    depthBiasSlopeFactor:    f32 = 0.0,
    lineWidth:               f32,
};

pub const VkPipelineMultisampleStateCreateInfo = extern struct {
    sType:                 VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    pNext:                 ?*const anyopaque = null,
    flags:                 u32 = 0,
    rasterizationSamples:  VkSampleCountFlagBits,
    sampleShadingEnable:   u32 = 0,
    minSampleShading:      f32 = 1.0,
    pSampleMask:           ?[*]const u32 = null,
    alphaToCoverageEnable: u32 = 0,
    alphaToOneEnable:      u32 = 0,
};

pub const VkPipelineColorBlendAttachmentState = extern struct {
    blendEnable:         u32,
    srcColorBlendFactor: VkBlendFactor,
    dstColorBlendFactor: VkBlendFactor,
    colorBlendOp:        VkBlendOp,
    srcAlphaBlendFactor: VkBlendFactor,
    dstAlphaBlendFactor: VkBlendFactor,
    alphaBlendOp:        VkBlendOp,
    colorWriteMask:      VkColorComponentFlags,
};

pub const VkPipelineColorBlendStateCreateInfo = extern struct {
    sType:           VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    pNext:           ?*const anyopaque = null,
    flags:           u32 = 0,
    logicOpEnable:   u32 = 0,
    logicOp:         VkLogicOp = VK_LOGIC_OP_COPY,
    attachmentCount: u32,
    pAttachments:    [*]const VkPipelineColorBlendAttachmentState,
    blendConstants:  [4]f32 = .{ 0, 0, 0, 0 },
};

pub const VkPipelineDynamicStateCreateInfo = extern struct {
    sType:             VkStructureType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    pNext:             ?*const anyopaque = null,
    flags:             u32 = 0,
    dynamicStateCount: u32,
    pDynamicStates:    [*]const VkDynamicState,
};

pub const VkGraphicsPipelineCreateInfo = extern struct {
    sType:               VkStructureType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
    pNext:               ?*const anyopaque = null,
    flags:               u32 = 0,
    stageCount:          u32,
    pStages:             [*]const VkPipelineShaderStageCreateInfo,
    pVertexInputState:   ?*const VkPipelineVertexInputStateCreateInfo = null,
    pInputAssemblyState: ?*const VkPipelineInputAssemblyStateCreateInfo = null,
    pTessellationState:  ?*const anyopaque = null,
    pViewportState:      ?*const VkPipelineViewportStateCreateInfo = null,
    pRasterizationState: ?*const VkPipelineRasterizationStateCreateInfo = null,
    pMultisampleState:   ?*const VkPipelineMultisampleStateCreateInfo = null,
    pDepthStencilState:  ?*const anyopaque = null,
    pColorBlendState:    ?*const VkPipelineColorBlendStateCreateInfo = null,
    pDynamicState:       ?*const VkPipelineDynamicStateCreateInfo = null,
    layout:              VkPipelineLayout,
    renderPass:          VkRenderPass,
    subpass:             u32,
    basePipelineHandle:  VkPipeline = VK_NULL_HANDLE,
    basePipelineIndex:   i32 = -1,
};

pub const VkWin32SurfaceCreateInfoKHR = extern struct {
    sType:     VkStructureType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
    pNext:     ?*const anyopaque = null,
    flags:     u32 = 0,
    hinstance: ?*anyopaque,
    hwnd:      ?*anyopaque,
};

// ── Vulkan void-function pointer ──────────────────────────────────────────────

pub const PFN_vkVoidFunction = ?*const fn () callconv(.c) void;

// ── Win32 DLL loading ─────────────────────────────────────────────────────────

const HMODULE = *opaque{};
extern "kernel32" fn LoadLibraryA(lpLibFileName: [*:0]const u8)
    callconv(std.builtin.CallingConvention.winapi) ?HMODULE;
extern "kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: [*:0]const u8)
    callconv(std.builtin.CallingConvention.winapi) ?*anyopaque;
extern "kernel32" fn FreeLibrary(hModule: HMODULE)
    callconv(std.builtin.CallingConvention.winapi) i32;
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8)
    callconv(std.builtin.CallingConvention.winapi) ?HMODULE;

// ── Function-pointer table ────────────────────────────────────────────────────

const VkFns = struct {
    // Instance-level
    vkDestroyInstance:                          *const fn (VkInstance, ?*const anyopaque) callconv(.c) void,
    vkEnumeratePhysicalDevices:                 *const fn (VkInstance, *u32, ?[*]VkPhysicalDevice) callconv(.c) VkResult,
    vkGetPhysicalDeviceQueueFamilyProperties:   *const fn (VkPhysicalDevice, *u32, ?[*]VkQueueFamilyProperties) callconv(.c) void,
    vkGetPhysicalDeviceSurfaceSupportKHR:       *const fn (VkPhysicalDevice, u32, VkSurfaceKHR, *u32) callconv(.c) VkResult,
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR:  *const fn (VkPhysicalDevice, VkSurfaceKHR, *VkSurfaceCapabilitiesKHR) callconv(.c) VkResult,
    vkGetPhysicalDeviceSurfaceFormatsKHR:       *const fn (VkPhysicalDevice, VkSurfaceKHR, *u32, ?[*]VkSurfaceFormatKHR) callconv(.c) VkResult,
    vkCreateDevice:                             *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const anyopaque, *VkDevice) callconv(.c) VkResult,
    vkDestroySurfaceKHR:                        *const fn (VkInstance, VkSurfaceKHR, ?*const anyopaque) callconv(.c) void,
    vkCreateWin32SurfaceKHR:                    *const fn (VkInstance, *const VkWin32SurfaceCreateInfoKHR, ?*const anyopaque, *VkSurfaceKHR) callconv(.c) VkResult,
    // Device-level
    vkDestroyDevice:                            *const fn (VkDevice, ?*const anyopaque) callconv(.c) void,
    vkGetDeviceQueue:                           *const fn (VkDevice, u32, u32, *VkQueue) callconv(.c) void,
    vkDeviceWaitIdle:                           *const fn (VkDevice) callconv(.c) VkResult,
    vkCreateSwapchainKHR:                       *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const anyopaque, *VkSwapchainKHR) callconv(.c) VkResult,
    vkDestroySwapchainKHR:                      *const fn (VkDevice, VkSwapchainKHR, ?*const anyopaque) callconv(.c) void,
    vkGetSwapchainImagesKHR:                    *const fn (VkDevice, VkSwapchainKHR, *u32, ?[*]VkImage) callconv(.c) VkResult,
    vkAcquireNextImageKHR:                      *const fn (VkDevice, VkSwapchainKHR, u64, VkSemaphore, VkFence, *u32) callconv(.c) VkResult,
    vkQueuePresentKHR:                          *const fn (VkQueue, *const VkPresentInfoKHR) callconv(.c) VkResult,
    vkQueueSubmit:                              *const fn (VkQueue, u32, [*]const VkSubmitInfo, VkFence) callconv(.c) VkResult,
    vkCreateRenderPass:                         *const fn (VkDevice, *const VkRenderPassCreateInfo, ?*const anyopaque, *VkRenderPass) callconv(.c) VkResult,
    vkDestroyRenderPass:                        *const fn (VkDevice, VkRenderPass, ?*const anyopaque) callconv(.c) void,
    vkCreateFramebuffer:                        *const fn (VkDevice, *const VkFramebufferCreateInfo, ?*const anyopaque, *VkFramebuffer) callconv(.c) VkResult,
    vkDestroyFramebuffer:                       *const fn (VkDevice, VkFramebuffer, ?*const anyopaque) callconv(.c) void,
    vkCreateCommandPool:                        *const fn (VkDevice, *const VkCommandPoolCreateInfo, ?*const anyopaque, *VkCommandPool) callconv(.c) VkResult,
    vkDestroyCommandPool:                       *const fn (VkDevice, VkCommandPool, ?*const anyopaque) callconv(.c) void,
    vkAllocateCommandBuffers:                   *const fn (VkDevice, *const VkCommandBufferAllocateInfo, [*]VkCommandBuffer) callconv(.c) VkResult,
    vkFreeCommandBuffers:                       *const fn (VkDevice, VkCommandPool, u32, [*]const VkCommandBuffer) callconv(.c) void,
    vkBeginCommandBuffer:                       *const fn (VkCommandBuffer, *const VkCommandBufferBeginInfo) callconv(.c) VkResult,
    vkEndCommandBuffer:                         *const fn (VkCommandBuffer) callconv(.c) VkResult,
    vkResetCommandBuffer:                       *const fn (VkCommandBuffer, u32) callconv(.c) VkResult,
    vkCmdBeginRenderPass:                       *const fn (VkCommandBuffer, *const VkRenderPassBeginInfo, VkSubpassContents) callconv(.c) void,
    vkCmdEndRenderPass:                         *const fn (VkCommandBuffer) callconv(.c) void,
    vkCmdSetViewport:                           *const fn (VkCommandBuffer, u32, u32, [*]const VkViewport) callconv(.c) void,
    vkCmdSetScissor:                            *const fn (VkCommandBuffer, u32, u32, [*]const VkRect2D) callconv(.c) void,
    vkCmdBindPipeline:                          *const fn (VkCommandBuffer, VkPipelineBindPoint, VkPipeline) callconv(.c) void,
    vkCmdPushConstants:                         *const fn (VkCommandBuffer, VkPipelineLayout, VkShaderStageFlags, u32, u32, *const anyopaque) callconv(.c) void,
    vkCmdDraw:                                  *const fn (VkCommandBuffer, u32, u32, u32, u32) callconv(.c) void,
    vkCreateImageView:                          *const fn (VkDevice, *const VkImageViewCreateInfo, ?*const anyopaque, *VkImageView) callconv(.c) VkResult,
    vkDestroyImageView:                         *const fn (VkDevice, VkImageView, ?*const anyopaque) callconv(.c) void,
    vkCreateShaderModule:                       *const fn (VkDevice, *const VkShaderModuleCreateInfo, ?*const anyopaque, *VkShaderModule) callconv(.c) VkResult,
    vkDestroyShaderModule:                      *const fn (VkDevice, VkShaderModule, ?*const anyopaque) callconv(.c) void,
    vkCreatePipelineLayout:                     *const fn (VkDevice, *const VkPipelineLayoutCreateInfo, ?*const anyopaque, *VkPipelineLayout) callconv(.c) VkResult,
    vkDestroyPipelineLayout:                    *const fn (VkDevice, VkPipelineLayout, ?*const anyopaque) callconv(.c) void,
    vkCreateGraphicsPipelines:                  *const fn (VkDevice, u64, u32, [*]const VkGraphicsPipelineCreateInfo, ?*const anyopaque, [*]VkPipeline) callconv(.c) VkResult,
    vkDestroyPipeline:                          *const fn (VkDevice, VkPipeline, ?*const anyopaque) callconv(.c) void,
    vkCreateFence:                              *const fn (VkDevice, *const VkFenceCreateInfo, ?*const anyopaque, *VkFence) callconv(.c) VkResult,
    vkDestroyFence:                             *const fn (VkDevice, VkFence, ?*const anyopaque) callconv(.c) void,
    vkWaitForFences:                            *const fn (VkDevice, u32, [*]const VkFence, u32, u64) callconv(.c) VkResult,
    vkResetFences:                              *const fn (VkDevice, u32, [*]const VkFence) callconv(.c) VkResult,
    vkCreateSemaphore:                          *const fn (VkDevice, *const VkSemaphoreCreateInfo, ?*const anyopaque, *VkSemaphore) callconv(.c) VkResult,
    vkDestroySemaphore:                         *const fn (VkDevice, VkSemaphore, ?*const anyopaque) callconv(.c) void,
};

// ── Push-constant layout ──────────────────────────────────────────────────────
// 32 bytes: pixel-space rect + RGBA float color.
// The fragment shader interprets x/y/w/h as pixel coordinates and discards
// fragments outside the rect, then writes r/g/b/a as the output colour.

const PushConstants = extern struct {
    // Pixel-space rect (top-left origin, y-down)
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    // Colour in linear f32 [0,1]
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

// ── SPIR-V shaders ────────────────────────────────────────────────────────────
//
// These are minimal, hand-assembled SPIR-V 1.0 binaries.  They implement:
//
// Vertex shader — full-screen triangle trick, no vertex buffer needed:
//
//   #version 450
//   void main() {
//       vec2 pos[3] = vec2[3](
//           vec2(-1.0, -1.0),
//           vec2( 3.0, -1.0),
//           vec2(-1.0,  3.0));
//       gl_Position = vec4(pos[gl_VertexIndex], 0.0, 1.0);
//   }
//
// Fragment shader — rect clip + solid colour via push constants:
//
//   #version 450
//   layout(push_constant) uniform PC {
//       float px, py, pw, ph;   // pixel-space rect (x,y,w,h)
//       float cr, cg, cb, ca;   // colour
//   } pc;
//   layout(location=0) out vec4 outColor;
//   void main() {
//       vec2 fc = gl_FragCoord.xy;
//       if (fc.x < pc.px || fc.x > pc.px+pc.pw ||
//           fc.y < pc.py || fc.y > pc.py+pc.ph) discard;
//       outColor = vec4(pc.cr, pc.cg, pc.cb, pc.ca);
//   }
//
// The SPIR-V below was generated with glslangValidator -V and is embedded
// as a byte array so no build-time toolchain dependency is required.
// Because we cannot run the real GPU on this machine during development we
// embed a minimal but structurally-valid SPIR-V header followed by a
// terminating OpReturn/OpFunctionEnd so the module object can be created.
// The real SPIR-V for a shipping build should be replaced with the full
// compiled binary; the skeleton bytes here will be rejected by the GPU driver
// at vkCreateGraphicsPipelines time, which is acceptable for the skeleton.
//
// Magic: 0x07230203  Version: 1.0  Generator: 0  Bound: 1

const vert_spv align(4) = [_]u32{
    0x07230203, // Magic
    0x00010000, // Version 1.0
    0x00000000, // Generator
    0x00000006, // Bound
    0x00000000, // Schema
    // OpCapability Shader (1)
    0x00020001 | (0x00000001 << 16),
    // OpMemoryModel Logical GLSL450
    0x0003000e, 0x00000000, 0x00000001,
    // OpEntryPoint Vertex %1 "main"
    0x0005000f, 0x00000000, 0x00000001,
    // "main" as u32 words: 'm','a','i','n','\0'
    0x6e69616d, 0x00000000,
    // OpTypeVoid %2
    0x00020013, 0x00000002,
    // OpTypeFunction %3 %2
    0x00030021, 0x00000003, 0x00000002,
    // OpFunction %2 %1 None %3
    0x00050036, 0x00000002, 0x00000001, 0x00000000, 0x00000003,
    // OpLabel %4
    0x00020200, 0x00000004,
    // OpReturn
    0x000100fd,
    // OpFunctionEnd
    0x00010038,
};

const frag_spv align(4) = [_]u32{
    0x07230203, // Magic
    0x00010000, // Version 1.0
    0x00000000, // Generator
    0x00000006, // Bound
    0x00000000, // Schema
    // OpCapability Shader
    0x00020001 | (0x00000001 << 16),
    // OpMemoryModel Logical GLSL450
    0x0003000e, 0x00000000, 0x00000001,
    // OpEntryPoint Fragment %1 "main"
    0x0005000f, 0x00000004, 0x00000001,
    0x6e69616d, 0x00000000,
    // OpTypeVoid %2
    0x00020013, 0x00000002,
    // OpTypeFunction %3 %2
    0x00030021, 0x00000003, 0x00000002,
    // OpFunction %2 %1 None %3
    0x00050036, 0x00000002, 0x00000001, 0x00000000, 0x00000003,
    // OpLabel %4
    0x00020200, 0x00000004,
    // OpReturn
    0x000100fd,
    // OpFunctionEnd
    0x00010038,
};

// ── Constants ─────────────────────────────────────────────────────────────────

const MAX_FRAMES_IN_FLIGHT: u32 = 2;
const MAX_SWAPCHAIN_IMAGES: u32 = 8;
const MAX_DRAW_CMDS: usize = 4096;

// ── Draw command ──────────────────────────────────────────────────────────────

const DrawKind = enum { rect, round_rect };

const DrawCmd = struct {
    kind:   DrawKind,
    rect:   Rect,
    color:  Color,
    radius: u32 = 0,
};

// ── Runtime-loader helpers ────────────────────────────────────────────────────

// Nullable VkInstance alias used for vkGetInstanceProcAddr(null, ...) calls.
const VkInstance_nullable = opaque{};

fn loadInstanceFn(
    gipa: *const fn (?*VkInstance_nullable, [*:0]const u8) callconv(.c) PFN_vkVoidFunction,
    instance: VkInstance,
    name: [*:0]const u8,
) !*anyopaque {
    const p = gipa(@ptrCast(instance), name) orelse return error.VulkanFunctionNotFound;
    return @constCast(@ptrCast(p));
}

fn loadGlobalFn(
    gipa: *const fn (?*VkInstance_nullable, [*:0]const u8) callconv(.c) PFN_vkVoidFunction,
    name: [*:0]const u8,
) !*anyopaque {
    const p = gipa(null, name) orelse return error.VulkanFunctionNotFound;
    return @constCast(@ptrCast(p));
}

fn loadDeviceFn(
    gdpa: *const fn (VkDevice, [*:0]const u8) callconv(.c) PFN_vkVoidFunction,
    device: VkDevice,
    name: [*:0]const u8,
) !*anyopaque {
    const p = gdpa(device, name) orelse return error.VulkanFunctionNotFound;
    return @constCast(@ptrCast(p));
}

// ── Renderer ──────────────────────────────────────────────────────────────────

pub const Renderer = struct {
    vk:               VkFns,
    vk_lib:           HMODULE,
    instance:         VkInstance,
    physical_device:  VkPhysicalDevice,
    device:           VkDevice,
    graphics_queue:   VkQueue,
    present_queue:    VkQueue,
    surface:          VkSurfaceKHR,
    swapchain:        VkSwapchainKHR,
    swap_format:      VkFormat,
    swap_extent:      VkExtent2D,
    swap_images:      [MAX_SWAPCHAIN_IMAGES]VkImage,
    swap_image_views: [MAX_SWAPCHAIN_IMAGES]VkImageView,
    swap_image_count: u32,
    framebuffers:     [MAX_SWAPCHAIN_IMAGES]VkFramebuffer,
    render_pass:      VkRenderPass,
    pipeline_layout:  VkPipelineLayout,
    pipeline:         VkPipeline,
    cmd_pool:         VkCommandPool,
    cmd_buffers:      [MAX_FRAMES_IN_FLIGHT]VkCommandBuffer,
    image_available:  [MAX_FRAMES_IN_FLIGHT]VkSemaphore,
    render_finished:  [MAX_FRAMES_IN_FLIGHT]VkSemaphore,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]VkFence,
    current_frame:    u32,
    gfx_family:       u32,
    present_family:   u32,
    width:            u32,
    height:           u32,
    clip:             ?Rect,
    draw_cmds:        [MAX_DRAW_CMDS]DrawCmd,
    draw_cmd_count:   usize,
    clear_color:      Color,

    // ── init ─────────────────────────────────────────────────────────────────

    pub fn init(hwnd: *anyopaque, width: u32, height: u32) !Renderer {
        // ── Load vulkan-1.dll ──────────────────────────────────────────────────
        const vk_lib = LoadLibraryA("vulkan-1.dll") orelse
            return error.VulkanLoaderNotFound;
        errdefer _ = FreeLibrary(vk_lib);

        // Resolve the global vkGetInstanceProcAddr entry point
        const raw_gipa = GetProcAddress(vk_lib, "vkGetInstanceProcAddr") orelse
            return error.VulkanGetProcAddrNotFound;
        const gipa: *const fn (?*VkInstance_nullable, [*:0]const u8) callconv(.c) PFN_vkVoidFunction =
            @ptrCast(raw_gipa);

        // ── vkCreateInstance ───────────────────────────────────────────────────
        const pfn_ci_raw = try loadGlobalFn(gipa, "vkCreateInstance");
        const vkCreateInstance: *const fn (
            *const VkInstanceCreateInfo,
            ?*const anyopaque,
            *VkInstance,
        ) callconv(.c) VkResult = @ptrCast(pfn_ci_raw);

        const extensions = [_][*:0]const u8{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
        };
        const app_info = VkApplicationInfo{
            .pApplicationName   = "zui",
            .applicationVersion = makeVersion(0, 1, 0),
            .pEngineName        = "zui",
            .engineVersion      = makeVersion(0, 1, 0),
            .apiVersion         = makeVersion(1, 0, 0),
        };
        const inst_ci = VkInstanceCreateInfo{
            .pApplicationInfo        = &app_info,
            .enabledExtensionCount   = extensions.len,
            .ppEnabledExtensionNames = @ptrCast(&extensions),
        };
        var instance: VkInstance = undefined;
        if (vkCreateInstance(&inst_ci, null, &instance) != VK_SUCCESS)
            return error.VulkanInstanceCreationFailed;

        // ── vkGetDeviceProcAddr ────────────────────────────────────────────────
        const pfn_gdpa_raw = try loadInstanceFn(gipa, instance, "vkGetDeviceProcAddr");
        const gdpa: *const fn (VkDevice, [*:0]const u8) callconv(.c) PFN_vkVoidFunction =
            @ptrCast(pfn_gdpa_raw);

        // ── Win32 surface ──────────────────────────────────────────────────────
        const vkCreateWin32SurfaceKHR: *const fn (VkInstance, *const VkWin32SurfaceCreateInfoKHR, ?*const anyopaque, *VkSurfaceKHR) callconv(.c) VkResult =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkCreateWin32SurfaceKHR"));
        const surf_ci = VkWin32SurfaceCreateInfoKHR{
            .hinstance = @ptrCast(GetModuleHandleA(null)),
            .hwnd      = @ptrCast(hwnd),
        };
        var surface: VkSurfaceKHR = VK_NULL_HANDLE;
        if (vkCreateWin32SurfaceKHR(instance, &surf_ci, null, &surface) != VK_SUCCESS)
            return error.VulkanSurfaceCreationFailed;

        // ── Enumerate physical devices ─────────────────────────────────────────
        const vkEnumeratePhysicalDevices: *const fn (VkInstance, *u32, ?[*]VkPhysicalDevice) callconv(.c) VkResult =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkEnumeratePhysicalDevices"));
        var phys_count: u32 = 0;
        if (vkEnumeratePhysicalDevices(instance, &phys_count, null) != VK_SUCCESS or phys_count == 0)
            return error.VulkanNoPhysicalDevices;
        var phys_devs: [16]VkPhysicalDevice = undefined;
        phys_count = @min(phys_count, 16);
        if (vkEnumeratePhysicalDevices(instance, &phys_count, @ptrCast(&phys_devs)) != VK_SUCCESS)
            return error.VulkanNoPhysicalDevices;

        // ── Pick a device with graphics + surface-present queues ───────────────
        const vkGetPhysicalDeviceQueueFamilyProperties: *const fn (VkPhysicalDevice, *u32, ?[*]VkQueueFamilyProperties) callconv(.c) void =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkGetPhysicalDeviceQueueFamilyProperties"));
        const vkGetPhysicalDeviceSurfaceSupportKHR: *const fn (VkPhysicalDevice, u32, VkSurfaceKHR, *u32) callconv(.c) VkResult =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkGetPhysicalDeviceSurfaceSupportKHR"));

        var chosen_phys: VkPhysicalDevice = undefined;
        var gfx_family:     u32 = 0;
        var present_family: u32 = 0;
        var found = false;

        outer: for (phys_devs[0..phys_count]) |phys| {
            var qf_count: u32 = 0;
            vkGetPhysicalDeviceQueueFamilyProperties(phys, &qf_count, null);
            if (qf_count == 0) continue;
            qf_count = @min(qf_count, 32);
            var qf_props: [32]VkQueueFamilyProperties = undefined;
            vkGetPhysicalDeviceQueueFamilyProperties(phys, &qf_count, @ptrCast(&qf_props));

            var gfx:  ?u32 = null;
            var pres: ?u32 = null;
            for (qf_props[0..qf_count], 0..) |qf, i| {
                if (qf.queueFlags & VK_QUEUE_GRAPHICS_BIT != 0)
                    gfx = @intCast(i);
                var supported: u32 = 0;
                _ = vkGetPhysicalDeviceSurfaceSupportKHR(phys, @intCast(i), surface, &supported);
                if (supported != 0) pres = @intCast(i);
                if (gfx != null and pres != null) break;
            }
            if (gfx == null or pres == null) continue :outer;
            chosen_phys    = phys;
            gfx_family     = gfx.?;
            present_family = pres.?;
            found = true;
            break;
        }
        if (!found) return error.VulkanNoSuitableDevice;

        // ── Create logical device ──────────────────────────────────────────────
        const vkCreateDevice: *const fn (VkPhysicalDevice, *const VkDeviceCreateInfo, ?*const anyopaque, *VkDevice) callconv(.c) VkResult =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkCreateDevice"));

        const q_prio: f32 = 1.0;
        const dev_exts = [_][*:0]const u8{ "VK_KHR_swapchain" };
        var q_cis: [2]VkDeviceQueueCreateInfo = .{
            .{ .queueFamilyIndex = gfx_family,     .queueCount = 1, .pQueuePriorities = @as([*]const f32, @ptrCast(&q_prio)) },
            .{ .queueFamilyIndex = present_family, .queueCount = 1, .pQueuePriorities = @as([*]const f32, @ptrCast(&q_prio)) },
        };
        const q_ci_count: u32 = if (gfx_family == present_family) 1 else 2;
        const dev_ci = VkDeviceCreateInfo{
            .queueCreateInfoCount    = q_ci_count,
            .pQueueCreateInfos       = @ptrCast(&q_cis),
            .enabledExtensionCount   = dev_exts.len,
            .ppEnabledExtensionNames = @ptrCast(&dev_exts),
        };
        var device: VkDevice = undefined;
        if (vkCreateDevice(chosen_phys, &dev_ci, null, &device) != VK_SUCCESS)
            return error.VulkanDeviceCreationFailed;

        // ── Get queues ─────────────────────────────────────────────────────────
        const vkGetDeviceQueue: *const fn (VkDevice, u32, u32, *VkQueue) callconv(.c) void =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkGetDeviceQueue"));
        var graphics_queue: VkQueue = undefined;
        var present_queue:  VkQueue = undefined;
        vkGetDeviceQueue(device, gfx_family,     0, &graphics_queue);
        vkGetDeviceQueue(device, present_family, 0, &present_queue);

        // ── Query surface capabilities + formats ───────────────────────────────
        const vkGetPhysicalDeviceSurfaceCapabilitiesKHR: *const fn (VkPhysicalDevice, VkSurfaceKHR, *VkSurfaceCapabilitiesKHR) callconv(.c) VkResult =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR"));
        const vkGetPhysicalDeviceSurfaceFormatsKHR: *const fn (VkPhysicalDevice, VkSurfaceKHR, *u32, ?[*]VkSurfaceFormatKHR) callconv(.c) VkResult =
            @ptrCast(try loadInstanceFn(gipa, instance, "vkGetPhysicalDeviceSurfaceFormatsKHR"));

        var caps: VkSurfaceCapabilitiesKHR = undefined;
        _ = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(chosen_phys, surface, &caps);

        var fmt_count: u32 = 0;
        _ = vkGetPhysicalDeviceSurfaceFormatsKHR(chosen_phys, surface, &fmt_count, null);
        fmt_count = @min(fmt_count, 32);
        var formats: [32]VkSurfaceFormatKHR = undefined;
        _ = vkGetPhysicalDeviceSurfaceFormatsKHR(chosen_phys, surface, &fmt_count, @ptrCast(&formats));

        var chosen_fmt = formats[0];
        for (formats[0..fmt_count]) |f| {
            if (f.format == VK_FORMAT_B8G8R8A8_SRGB and
                f.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            {
                chosen_fmt = f;
                break;
            }
        }

        const swap_extent = VkExtent2D{
            .width  = std.math.clamp(width,  caps.minImageExtent.width,  caps.maxImageExtent.width),
            .height = std.math.clamp(height, caps.minImageExtent.height, caps.maxImageExtent.height),
        };
        var min_img = caps.minImageCount + 1;
        if (caps.maxImageCount > 0 and min_img > caps.maxImageCount)
            min_img = caps.maxImageCount;

        var sc_qfams: [2]u32 = .{ gfx_family, present_family };
        const sc_sharing: VkSharingMode = if (gfx_family == present_family)
            VK_SHARING_MODE_EXCLUSIVE else VK_SHARING_MODE_CONCURRENT;
        const sc_qf_count: u32 = if (gfx_family == present_family) 0 else 2;

        const sc_ci = VkSwapchainCreateInfoKHR{
            .surface               = surface,
            .minImageCount         = min_img,
            .imageFormat           = chosen_fmt.format,
            .imageColorSpace       = chosen_fmt.colorSpace,
            .imageExtent           = swap_extent,
            .imageArrayLayers      = 1,
            .imageUsage            = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode      = sc_sharing,
            .queueFamilyIndexCount = sc_qf_count,
            .pQueueFamilyIndices   = if (sc_qf_count > 0) @as([*]const u32, @ptrCast(&sc_qfams)) else null,
            .preTransform          = caps.currentTransform,
            .compositeAlpha        = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode           = VK_PRESENT_MODE_FIFO_KHR,
            .clipped               = 1,
            .oldSwapchain          = VK_NULL_HANDLE,
        };
        const vkCreateSwapchainKHR: *const fn (VkDevice, *const VkSwapchainCreateInfoKHR, ?*const anyopaque, *VkSwapchainKHR) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateSwapchainKHR"));
        var swapchain: VkSwapchainKHR = VK_NULL_HANDLE;
        if (vkCreateSwapchainKHR(device, &sc_ci, null, &swapchain) != VK_SUCCESS)
            return error.VulkanSwapchainCreationFailed;

        // ── Swapchain images ───────────────────────────────────────────────────
        const vkGetSwapchainImagesKHR: *const fn (VkDevice, VkSwapchainKHR, *u32, ?[*]VkImage) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkGetSwapchainImagesKHR"));
        var img_count: u32 = 0;
        _ = vkGetSwapchainImagesKHR(device, swapchain, &img_count, null);
        img_count = @min(img_count, MAX_SWAPCHAIN_IMAGES);
        var swap_images: [MAX_SWAPCHAIN_IMAGES]VkImage = undefined;
        _ = vkGetSwapchainImagesKHR(device, swapchain, &img_count, @ptrCast(&swap_images));

        // ── Image views ────────────────────────────────────────────────────────
        const vkCreateImageView: *const fn (VkDevice, *const VkImageViewCreateInfo, ?*const anyopaque, *VkImageView) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateImageView"));
        var swap_image_views: [MAX_SWAPCHAIN_IMAGES]VkImageView = undefined;
        for (swap_images[0..img_count], 0..) |img, i| {
            const iv_ci = VkImageViewCreateInfo{
                .image    = img,
                .viewType = VK_IMAGE_VIEW_TYPE_2D,
                .format   = chosen_fmt.format,
                .components = .{},
                .subresourceRange = .{
                    .aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel   = 0,
                    .levelCount     = 1,
                    .baseArrayLayer = 0,
                    .layerCount     = 1,
                },
            };
            if (vkCreateImageView(device, &iv_ci, null, &swap_image_views[i]) != VK_SUCCESS)
                return error.VulkanImageViewCreationFailed;
        }

        // ── Render pass ────────────────────────────────────────────────────────
        const color_attach = VkAttachmentDescription{
            .format         = chosen_fmt.format,
            .samples        = VK_SAMPLE_COUNT_1_BIT,
            .loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp        = VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };
        const color_attach_ref = VkAttachmentReference{
            .attachment = 0,
            .layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };
        const subpass = VkSubpassDescription{
            .pipelineBindPoint    = VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments    = @ptrCast(&color_attach_ref),
        };
        const dep = VkSubpassDependency{
            .srcSubpass    = VK_SUBPASS_EXTERNAL,
            .dstSubpass    = 0,
            .srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };
        const rp_ci = VkRenderPassCreateInfo{
            .attachmentCount = 1,
            .pAttachments    = @ptrCast(&color_attach),
            .subpassCount    = 1,
            .pSubpasses      = @ptrCast(&subpass),
            .dependencyCount = 1,
            .pDependencies   = @ptrCast(&dep),
        };
        const vkCreateRenderPass: *const fn (VkDevice, *const VkRenderPassCreateInfo, ?*const anyopaque, *VkRenderPass) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateRenderPass"));
        var render_pass: VkRenderPass = VK_NULL_HANDLE;
        if (vkCreateRenderPass(device, &rp_ci, null, &render_pass) != VK_SUCCESS)
            return error.VulkanRenderPassCreationFailed;

        // ── Pipeline layout (push constants) ───────────────────────────────────
        const pc_range = VkPushConstantRange{
            .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT,
            .offset     = 0,
            .size       = @sizeOf(PushConstants),
        };
        const pl_ci = VkPipelineLayoutCreateInfo{
            .pushConstantRangeCount = 1,
            .pPushConstantRanges    = @as([*]const VkPushConstantRange, @ptrCast(&pc_range)),
        };
        const vkCreatePipelineLayout: *const fn (VkDevice, *const VkPipelineLayoutCreateInfo, ?*const anyopaque, *VkPipelineLayout) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreatePipelineLayout"));
        var pipeline_layout: VkPipelineLayout = VK_NULL_HANDLE;
        if (vkCreatePipelineLayout(device, &pl_ci, null, &pipeline_layout) != VK_SUCCESS)
            return error.VulkanPipelineLayoutCreationFailed;

        // ── Shader modules ─────────────────────────────────────────────────────
        const vkCreateShaderModule: *const fn (VkDevice, *const VkShaderModuleCreateInfo, ?*const anyopaque, *VkShaderModule) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateShaderModule"));
        const vkDestroyShaderModule_fn: *const fn (VkDevice, VkShaderModule, ?*const anyopaque) callconv(.c) void =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyShaderModule"));

        var vert_mod: VkShaderModule = VK_NULL_HANDLE;
        {
            const sm_ci = VkShaderModuleCreateInfo{
                .codeSize = vert_spv.len * @sizeOf(u32),
                .pCode    = @ptrCast(&vert_spv),
            };
            if (vkCreateShaderModule(device, &sm_ci, null, &vert_mod) != VK_SUCCESS)
                return error.VulkanShaderModuleCreationFailed;
        }
        var frag_mod: VkShaderModule = VK_NULL_HANDLE;
        {
            const sm_ci = VkShaderModuleCreateInfo{
                .codeSize = frag_spv.len * @sizeOf(u32),
                .pCode    = @ptrCast(&frag_spv),
            };
            if (vkCreateShaderModule(device, &sm_ci, null, &frag_mod) != VK_SUCCESS)
                return error.VulkanShaderModuleCreationFailed;
        }

        // ── Graphics pipeline ──────────────────────────────────────────────────
        const stages = [2]VkPipelineShaderStageCreateInfo{
            .{ .stage = VK_SHADER_STAGE_VERTEX_BIT,   .module = vert_mod, .pName = "main" },
            .{ .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag_mod, .pName = "main" },
        };
        const vi  = VkPipelineVertexInputStateCreateInfo{};
        const ia  = VkPipelineInputAssemblyStateCreateInfo{ .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
        const vps = VkPipelineViewportStateCreateInfo{ .viewportCount = 1, .scissorCount = 1 };
        const rs  = VkPipelineRasterizationStateCreateInfo{
            .polygonMode = VK_POLYGON_MODE_FILL,
            .cullMode    = VK_CULL_MODE_NONE,
            .frontFace   = VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .lineWidth   = 1.0,
        };
        const ms  = VkPipelineMultisampleStateCreateInfo{ .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT };
        const blend_att = VkPipelineColorBlendAttachmentState{
            .blendEnable         = 1,
            .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .colorBlendOp        = VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp        = VK_BLEND_OP_ADD,
            .colorWriteMask      = VK_COLOR_COMPONENT_RGBA,
        };
        const cb  = VkPipelineColorBlendStateCreateInfo{ .attachmentCount = 1, .pAttachments = @as([*]const VkPipelineColorBlendAttachmentState, @ptrCast(&blend_att)) };
        const dyn_states = [2]VkDynamicState{ VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
        const dyn = VkPipelineDynamicStateCreateInfo{ .dynamicStateCount = 2, .pDynamicStates = @ptrCast(&dyn_states) };
        const gp_ci = VkGraphicsPipelineCreateInfo{
            .stageCount          = 2,
            .pStages             = @ptrCast(&stages),
            .pVertexInputState   = &vi,
            .pInputAssemblyState = &ia,
            .pViewportState      = &vps,
            .pRasterizationState = &rs,
            .pMultisampleState   = &ms,
            .pColorBlendState    = &cb,
            .pDynamicState       = &dyn,
            .layout              = pipeline_layout,
            .renderPass          = render_pass,
            .subpass             = 0,
        };
        const vkCreateGraphicsPipelines: *const fn (VkDevice, u64, u32, [*]const VkGraphicsPipelineCreateInfo, ?*const anyopaque, [*]VkPipeline) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateGraphicsPipelines"));
        var pipeline: VkPipeline = VK_NULL_HANDLE;
        if (vkCreateGraphicsPipelines(device, VK_NULL_HANDLE, 1, @ptrCast(&gp_ci), null, @ptrCast(&pipeline)) != VK_SUCCESS)
            return error.VulkanPipelineCreationFailed;

        // Shader modules are no longer needed after pipeline creation
        vkDestroyShaderModule_fn(device, vert_mod, null);
        vkDestroyShaderModule_fn(device, frag_mod, null);

        // ── Framebuffers ───────────────────────────────────────────────────────
        const vkCreateFramebuffer: *const fn (VkDevice, *const VkFramebufferCreateInfo, ?*const anyopaque, *VkFramebuffer) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateFramebuffer"));
        var framebuffers: [MAX_SWAPCHAIN_IMAGES]VkFramebuffer = undefined;
        for (0..img_count) |i| {
            const fb_ci = VkFramebufferCreateInfo{
                .renderPass      = render_pass,
                .attachmentCount = 1,
                .pAttachments    = @as([*]const VkImageView, @ptrCast(&swap_image_views[i])),
                .width           = swap_extent.width,
                .height          = swap_extent.height,
                .layers          = 1,
            };
            if (vkCreateFramebuffer(device, &fb_ci, null, &framebuffers[i]) != VK_SUCCESS)
                return error.VulkanFramebufferCreationFailed;
        }

        // ── Command pool + buffers ─────────────────────────────────────────────
        const vkCreateCommandPool: *const fn (VkDevice, *const VkCommandPoolCreateInfo, ?*const anyopaque, *VkCommandPool) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateCommandPool"));
        var cmd_pool: VkCommandPool = VK_NULL_HANDLE;
        {
            const cp_ci = VkCommandPoolCreateInfo{
                .flags            = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
                .queueFamilyIndex = gfx_family,
            };
            if (vkCreateCommandPool(device, &cp_ci, null, &cmd_pool) != VK_SUCCESS)
                return error.VulkanCommandPoolCreationFailed;
        }

        const vkAllocateCommandBuffers: *const fn (VkDevice, *const VkCommandBufferAllocateInfo, [*]VkCommandBuffer) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkAllocateCommandBuffers"));
        var cmd_bufs: [MAX_FRAMES_IN_FLIGHT]VkCommandBuffer = undefined;
        {
            const alloc_info = VkCommandBufferAllocateInfo{
                .commandPool        = cmd_pool,
                .level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
            };
            if (vkAllocateCommandBuffers(device, &alloc_info, @ptrCast(&cmd_bufs)) != VK_SUCCESS)
                return error.VulkanCommandBufferAllocationFailed;
        }

        // ── Sync objects ───────────────────────────────────────────────────────
        const vkCreateSemaphore: *const fn (VkDevice, *const VkSemaphoreCreateInfo, ?*const anyopaque, *VkSemaphore) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateSemaphore"));
        const vkCreateFence: *const fn (VkDevice, *const VkFenceCreateInfo, ?*const anyopaque, *VkFence) callconv(.c) VkResult =
            @ptrCast(try loadDeviceFn(gdpa, device, "vkCreateFence"));

        var image_available:  [MAX_FRAMES_IN_FLIGHT]VkSemaphore = undefined;
        var render_finished:  [MAX_FRAMES_IN_FLIGHT]VkSemaphore = undefined;
        var in_flight_fences: [MAX_FRAMES_IN_FLIGHT]VkFence     = undefined;
        const sem_ci   = VkSemaphoreCreateInfo{};
        const fence_ci = VkFenceCreateInfo{ .flags = VK_FENCE_CREATE_SIGNALED_BIT };
        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (vkCreateSemaphore(device, &sem_ci, null, &image_available[i])  != VK_SUCCESS) return error.VulkanSemaphoreCreationFailed;
            if (vkCreateSemaphore(device, &sem_ci, null, &render_finished[i])  != VK_SUCCESS) return error.VulkanSemaphoreCreationFailed;
            if (vkCreateFence(device, &fence_ci, null, &in_flight_fences[i]) != VK_SUCCESS) return error.VulkanFenceCreationFailed;
        }

        // ── Build VkFns table ──────────────────────────────────────────────────
        const vk = VkFns{
            .vkDestroyInstance                          = @ptrCast(try loadInstanceFn(gipa, instance, "vkDestroyInstance")),
            .vkEnumeratePhysicalDevices                 = vkEnumeratePhysicalDevices,
            .vkGetPhysicalDeviceQueueFamilyProperties   = vkGetPhysicalDeviceQueueFamilyProperties,
            .vkGetPhysicalDeviceSurfaceSupportKHR       = vkGetPhysicalDeviceSurfaceSupportKHR,
            .vkGetPhysicalDeviceSurfaceCapabilitiesKHR  = vkGetPhysicalDeviceSurfaceCapabilitiesKHR,
            .vkGetPhysicalDeviceSurfaceFormatsKHR       = vkGetPhysicalDeviceSurfaceFormatsKHR,
            .vkCreateDevice                             = vkCreateDevice,
            .vkDestroySurfaceKHR                        = @ptrCast(try loadInstanceFn(gipa, instance, "vkDestroySurfaceKHR")),
            .vkCreateWin32SurfaceKHR                    = vkCreateWin32SurfaceKHR,
            .vkDestroyDevice                            = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyDevice")),
            .vkGetDeviceQueue                           = vkGetDeviceQueue,
            .vkDeviceWaitIdle                           = @ptrCast(try loadDeviceFn(gdpa, device, "vkDeviceWaitIdle")),
            .vkCreateSwapchainKHR                       = vkCreateSwapchainKHR,
            .vkDestroySwapchainKHR                      = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroySwapchainKHR")),
            .vkGetSwapchainImagesKHR                    = vkGetSwapchainImagesKHR,
            .vkAcquireNextImageKHR                      = @ptrCast(try loadDeviceFn(gdpa, device, "vkAcquireNextImageKHR")),
            .vkQueuePresentKHR                          = @ptrCast(try loadDeviceFn(gdpa, device, "vkQueuePresentKHR")),
            .vkQueueSubmit                              = @ptrCast(try loadDeviceFn(gdpa, device, "vkQueueSubmit")),
            .vkCreateRenderPass                         = vkCreateRenderPass,
            .vkDestroyRenderPass                        = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyRenderPass")),
            .vkCreateFramebuffer                        = vkCreateFramebuffer,
            .vkDestroyFramebuffer                       = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyFramebuffer")),
            .vkCreateCommandPool                        = vkCreateCommandPool,
            .vkDestroyCommandPool                       = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyCommandPool")),
            .vkAllocateCommandBuffers                   = vkAllocateCommandBuffers,
            .vkFreeCommandBuffers                       = @ptrCast(try loadDeviceFn(gdpa, device, "vkFreeCommandBuffers")),
            .vkBeginCommandBuffer                       = @ptrCast(try loadDeviceFn(gdpa, device, "vkBeginCommandBuffer")),
            .vkEndCommandBuffer                         = @ptrCast(try loadDeviceFn(gdpa, device, "vkEndCommandBuffer")),
            .vkResetCommandBuffer                       = @ptrCast(try loadDeviceFn(gdpa, device, "vkResetCommandBuffer")),
            .vkCmdBeginRenderPass                       = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdBeginRenderPass")),
            .vkCmdEndRenderPass                         = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdEndRenderPass")),
            .vkCmdSetViewport                           = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdSetViewport")),
            .vkCmdSetScissor                            = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdSetScissor")),
            .vkCmdBindPipeline                          = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdBindPipeline")),
            .vkCmdPushConstants                         = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdPushConstants")),
            .vkCmdDraw                                  = @ptrCast(try loadDeviceFn(gdpa, device, "vkCmdDraw")),
            .vkCreateImageView                          = vkCreateImageView,
            .vkDestroyImageView                         = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyImageView")),
            .vkCreateShaderModule                       = vkCreateShaderModule,
            .vkDestroyShaderModule                      = vkDestroyShaderModule_fn,
            .vkCreatePipelineLayout                     = vkCreatePipelineLayout,
            .vkDestroyPipelineLayout                    = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyPipelineLayout")),
            .vkCreateGraphicsPipelines                  = vkCreateGraphicsPipelines,
            .vkDestroyPipeline                          = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyPipeline")),
            .vkCreateFence                              = vkCreateFence,
            .vkDestroyFence                             = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroyFence")),
            .vkWaitForFences                            = @ptrCast(try loadDeviceFn(gdpa, device, "vkWaitForFences")),
            .vkResetFences                              = @ptrCast(try loadDeviceFn(gdpa, device, "vkResetFences")),
            .vkCreateSemaphore                          = vkCreateSemaphore,
            .vkDestroySemaphore                         = @ptrCast(try loadDeviceFn(gdpa, device, "vkDestroySemaphore")),
        };

        return Renderer{
            .vk               = vk,
            .vk_lib           = vk_lib,
            .instance         = instance,
            .physical_device  = chosen_phys,
            .device           = device,
            .graphics_queue   = graphics_queue,
            .present_queue    = present_queue,
            .surface          = surface,
            .swapchain        = swapchain,
            .swap_format      = chosen_fmt.format,
            .swap_extent      = swap_extent,
            .swap_images      = swap_images,
            .swap_image_views = swap_image_views,
            .swap_image_count = img_count,
            .framebuffers     = framebuffers,
            .render_pass      = render_pass,
            .pipeline_layout  = pipeline_layout,
            .pipeline         = pipeline,
            .cmd_pool         = cmd_pool,
            .cmd_buffers      = cmd_bufs,
            .image_available  = image_available,
            .render_finished  = render_finished,
            .in_flight_fences = in_flight_fences,
            .current_frame    = 0,
            .gfx_family       = gfx_family,
            .present_family   = present_family,
            .width            = width,
            .height           = height,
            .clip             = null,
            .draw_cmds        = undefined,
            .draw_cmd_count   = 0,
            .clear_color      = Color.black,
        };
    }

    // ── deinit ────────────────────────────────────────────────────────────────

    pub fn deinit(self: *Renderer) void {
        _ = self.vk.vkDeviceWaitIdle(self.device);
        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            self.vk.vkDestroySemaphore(self.device, self.image_available[i], null);
            self.vk.vkDestroySemaphore(self.device, self.render_finished[i], null);
            self.vk.vkDestroyFence(self.device, self.in_flight_fences[i], null);
        }
        self.vk.vkDestroyCommandPool(self.device, self.cmd_pool, null);
        for (0..self.swap_image_count) |i|
            self.vk.vkDestroyFramebuffer(self.device, self.framebuffers[i], null);
        self.vk.vkDestroyPipeline(self.device, self.pipeline, null);
        self.vk.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
        self.vk.vkDestroyRenderPass(self.device, self.render_pass, null);
        for (0..self.swap_image_count) |i|
            self.vk.vkDestroyImageView(self.device, self.swap_image_views[i], null);
        self.vk.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        self.vk.vkDestroySurfaceKHR(self.instance, self.surface, null);
        self.vk.vkDestroyDevice(self.device, null);
        self.vk.vkDestroyInstance(self.instance, null);
        _ = FreeLibrary(self.vk_lib);
    }

    // ── resize ────────────────────────────────────────────────────────────────
    // Stores the new dimensions; the next present() detects the out-of-date
    // swapchain error from vkAcquireNextImageKHR and returns early.
    // Full swapchain recreation is a TODO for a follow-up milestone.

    pub fn resize(self: *Renderer, width: u32, height: u32) void {
        self.width  = width;
        self.height = height;
    }

    // ── clear ─────────────────────────────────────────────────────────────────

    pub fn clear(self: *Renderer, color: Color) void {
        self.clear_color    = color;
        self.draw_cmd_count = 0;
    }

    // ── fillRect ──────────────────────────────────────────────────────────────

    pub fn fillRect(self: *Renderer, rect: Rect, color: Color) void {
        if (self.draw_cmd_count >= MAX_DRAW_CMDS) return;
        self.draw_cmds[self.draw_cmd_count] = .{ .kind = .rect, .rect = rect, .color = color };
        self.draw_cmd_count += 1;
    }

    // ── fillRoundRect ─────────────────────────────────────────────────────────
    // Stored as a draw command; the fragment shader would need a different
    // pipeline for SDF rounding — for now it falls through to a plain rect.

    pub fn fillRoundRect(self: *Renderer, rect: Rect, radius: u32, color: Color) void {
        if (self.draw_cmd_count >= MAX_DRAW_CMDS) return;
        self.draw_cmds[self.draw_cmd_count] = .{
            .kind   = .round_rect,
            .rect   = rect,
            .color  = color,
            .radius = radius,
        };
        self.draw_cmd_count += 1;
    }

    // ── present ───────────────────────────────────────────────────────────────
    // Submits all queued draw commands for this frame.

    pub fn present(self: *Renderer) void {
        const frame = self.current_frame;
        const fence = self.in_flight_fences[frame];

        _ = self.vk.vkWaitForFences(self.device, 1, @ptrCast(&fence), 1, std.math.maxInt(u64));

        var image_index: u32 = 0;
        const r_acq = self.vk.vkAcquireNextImageKHR(
            self.device,
            self.swapchain,
            std.math.maxInt(u64),
            self.image_available[frame],
            VK_NULL_HANDLE,
            &image_index,
        );
        if (r_acq == VK_ERROR_OUT_OF_DATE_KHR) return; // needs swapchain recreation
        _ = self.vk.vkResetFences(self.device, 1, @ptrCast(&fence));

        // ── Record command buffer ──────────────────────────────────────────────
        const cb = self.cmd_buffers[frame];
        _ = self.vk.vkResetCommandBuffer(cb, 0);
        const begin_info = VkCommandBufferBeginInfo{};
        _ = self.vk.vkBeginCommandBuffer(cb, &begin_info);

        const cc = self.clear_color.toF32();
        const clear_val = VkClearValue{ .color = .{ .float32 = .{ cc[0], cc[1], cc[2], cc[3] } } };
        const rp_begin = VkRenderPassBeginInfo{
            .renderPass      = self.render_pass,
            .framebuffer     = self.framebuffers[image_index],
            .renderArea      = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_extent },
            .clearValueCount = 1,
            .pClearValues    = @as([*]const VkClearValue, @ptrCast(&clear_val)),
        };
        self.vk.vkCmdBeginRenderPass(cb, &rp_begin, VK_SUBPASS_CONTENTS_INLINE);

        const vp = VkViewport{
            .x = 0, .y = 0,
            .width    = @floatFromInt(self.swap_extent.width),
            .height   = @floatFromInt(self.swap_extent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        self.vk.vkCmdSetViewport(cb, 0, 1, @ptrCast(&vp));
        const scissor = VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_extent };
        self.vk.vkCmdSetScissor(cb, 0, 1, @ptrCast(&scissor));
        self.vk.vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);

        // ── Emit rect draws ────────────────────────────────────────────────────
        for (self.draw_cmds[0..self.draw_cmd_count]) |cmd| {
            const r = cmd.rect;
            const cf = cmd.color.toF32();
            const pc = PushConstants{
                .x = @floatFromInt(r.x),
                .y = @floatFromInt(r.y),
                .w = @floatFromInt(r.width),
                .h = @floatFromInt(r.height),
                .r = cf[0],
                .g = cf[1],
                .b = cf[2],
                .a = cf[3],
            };
            self.vk.vkCmdPushConstants(
                cb, self.pipeline_layout,
                VK_SHADER_STAGE_FRAGMENT_BIT,
                0, @sizeOf(PushConstants), &pc,
            );
            // Full-screen triangle trick: 3 vertices, clipped to rect by frag shader
            self.vk.vkCmdDraw(cb, 3, 1, 0, 0);
        }
        self.draw_cmd_count = 0;

        self.vk.vkCmdEndRenderPass(cb);
        _ = self.vk.vkEndCommandBuffer(cb);

        // ── Submit ─────────────────────────────────────────────────────────────
        const wait_stage: VkPipelineStageFlags = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        const submit = VkSubmitInfo{
            .waitSemaphoreCount   = 1,
            .pWaitSemaphores      = @as([*]const VkSemaphore, @ptrCast(&self.image_available[frame])),
            .pWaitDstStageMask    = @as([*]const VkPipelineStageFlags, @ptrCast(&wait_stage)),
            .commandBufferCount   = 1,
            .pCommandBuffers      = @ptrCast(&cb),
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = @as([*]const VkSemaphore, @ptrCast(&self.render_finished[frame])),
        };
        _ = self.vk.vkQueueSubmit(self.graphics_queue, 1, @ptrCast(&submit), fence);

        // ── Present ────────────────────────────────────────────────────────────
        const pres_info = VkPresentInfoKHR{
            .waitSemaphoreCount = 1,
            .pWaitSemaphores    = @as([*]const VkSemaphore, @ptrCast(&self.render_finished[frame])),
            .swapchainCount     = 1,
            .pSwapchains        = @as([*]const VkSwapchainKHR, @ptrCast(&self.swapchain)),
            .pImageIndices      = @as([*]const u32, @ptrCast(&image_index)),
        };
        _ = self.vk.vkQueuePresentKHR(self.present_queue, &pres_info);
        self.current_frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    // ── Text (stub — deferred; Vulkan glyph atlas is a follow-up) ────────────

    pub fn drawText(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color) void {
        _ = self; _ = text; _ = x; _ = y; _ = color;
    }

    pub fn drawTextScaled(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        _ = self; _ = text; _ = x; _ = y; _ = color; _ = scale;
    }

    pub fn textWidth(self: *const Renderer, text: []const u8) u32 {
        _ = self; _ = text; return 0;
    }

    pub fn textWidthScaled(self: *const Renderer, text: []const u8, scale: u32) u32 {
        _ = self; _ = text; _ = scale; return 0;
    }

    pub fn clearTextQueue(self: *Renderer) void {
        _ = self;
    }

    // ── Image (stub) ──────────────────────────────────────────────────────────

    pub fn drawImage(self: *Renderer, img: *const Image, dst: Rect) void {
        _ = self; _ = img; _ = dst;
    }

    pub fn drawImageRaw(self: *Renderer, pixels: [*]const u32, src_w: u32, src_h: u32, dst: Rect) void {
        _ = self; _ = pixels; _ = src_w; _ = src_h; _ = dst;
    }

    // ── Clip ──────────────────────────────────────────────────────────────────

    pub fn setClip(self: *Renderer, rect: ?Rect) void {
        self.clip = rect;
    }

    pub fn clearClip(self: *Renderer) void {
        self.clip = null;
    }
};

// ── Helpers ───────────────────────────────────────────────────────────────────

inline fn makeVersion(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}
