# SCons profile for a single-threaded Godot Web release template.
platform = "web"
target = "template_release"
threads = "no"
production = "yes"
optimize = "size_extra"

# The demos do not use navigation, XR, or imported 3D model loaders.
disable_navigation_2d = "yes"
disable_navigation_3d = "yes"
disable_xr = "yes"
module_openxr_enabled = "no"
module_webxr_enabled = "no"
module_fbx_enabled = "no"
module_gltf_enabled = "no"
module_csg_enabled = "no"
module_theora_enabled = "no"
