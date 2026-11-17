"""A small stand-in for the editor's `unreal` module, just large enough for unreal/cbr_unreal.py.

It holds actors in a list and remembers what was set on them. It follows the names in Epic's Python
API reference for UE 5, but it is written from that reference, not checked against a running editor:
passing with this stand-in shows the script's own logic is right, not that every engine call exists
under that name in your engine version.
"""
from __future__ import annotations


class Vector:
    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)


class Rotator:
    def __init__(self, roll=0.0, pitch=0.0, yaw=0.0):
        self.roll, self.pitch, self.yaw = float(roll), float(pitch), float(yaw)


class LinearColor:
    def __init__(self, r=0.0, g=0.0, b=0.0, a=1.0):
        self.r, self.g, self.b, self.a = float(r), float(g), float(b), float(a)


class Color:
    def __init__(self, b=0, g=0, r=0, a=255):
        self.b, self.g, self.r, self.a = int(b), int(g), int(r), int(a)


class Name(str):
    pass


class _Enum:
    def __init__(self, name):
        self.name = name


class LightUnits:
    UNITLESS = _Enum("UNITLESS")
    CANDELAS = _Enum("CANDELAS")


class HorizTextAligment:
    EHTA_CENTER = _Enum("EHTA_CENTER")


class _Object:
    def __init__(self):
        self.properties = {}

    def get_editor_property(self, name):
        return self.properties.get(name)

    def set_editor_property(self, name, value):
        self.properties[name] = value


class _Asset(_Object):
    def __init__(self, path):
        super().__init__()
        self.path = path

    def get_path_name(self):
        return self.path + "." + self.path.rsplit("/", 1)[-1]

    def get_name(self):
        return self.path.rsplit("/", 1)[-1]


class StaticMesh(_Asset):
    pass


class Material(_Asset):
    pass


class MaterialInstanceConstant(_Asset):
    def __init__(self, path):
        super().__init__(path)
        self.parent = None
        self.vectors = {}


class MaterialInstanceConstantFactoryNew:
    pass


class _Component(_Object):
    pass


class StaticMeshComponent(_Component):
    def __init__(self):
        super().__init__()
        self.materials = {}

    def set_static_mesh(self, mesh):
        self.properties["static_mesh"] = mesh

    def set_material(self, index, material):
        self.materials[index] = material

    def get_material(self, index):
        return self.materials.get(index)


class PointLightComponent(_Component):
    def __init__(self):
        super().__init__()
        self.properties.update(intensity=5000.0, attenuation_radius=1000.0, light_color=Color(255, 255, 255, 255),
                               intensity_units=LightUnits.CANDELAS)

    def set_intensity(self, value):
        self.properties["intensity"] = float(value)

    def set_attenuation_radius(self, value):
        self.properties["attenuation_radius"] = float(value)

    def set_light_color(self, color, srgb=True):
        self.properties["light_color"] = Color(b=round(color.b * 255), g=round(color.g * 255), r=round(color.r * 255))


class TextRenderComponent(_Component):
    def __init__(self):
        super().__init__()
        self.properties.update(text="Text", world_size=26.0, text_render_color=Color(255, 255, 255, 255))

    def set_text(self, text):
        self.properties["text"] = str(text)

    def set_world_size(self, size):
        self.properties["world_size"] = float(size)

    def set_text_render_color(self, color):
        self.properties["text_render_color"] = color

    def set_horizontal_alignment(self, alignment):
        self.properties["horizontal_alignment"] = alignment


class Actor(_Object):
    def __init__(self, location, rotation):
        super().__init__()
        self.location, self.rotation, self.scale = location, rotation, Vector(1, 1, 1)
        self.label, self.folder = "", ""
        self.properties["tags"] = []
        self.components = []

    def get_actor_location(self):
        return self.location

    def get_actor_rotation(self):
        return self.rotation

    def get_actor_scale3d(self):
        return self.scale

    def set_actor_scale3d(self, scale):
        self.scale = scale

    def set_actor_location(self, location, sweep=False, teleport=True):
        self.location = location

    def set_actor_label(self, label):
        self.label = label

    def get_actor_label(self):
        return self.label

    def set_folder_path(self, folder):
        self.folder = folder

    def get_component_by_class(self, component_class):
        for component in self.components:
            if isinstance(component, component_class):
                return component
        return None


class StaticMeshActor(Actor):
    def __init__(self, location, rotation):
        super().__init__(location, rotation)
        self.static_mesh_component = StaticMeshComponent()
        self.components.append(self.static_mesh_component)


class PointLight(Actor):
    def __init__(self, location, rotation):
        super().__init__(location, rotation)
        self.components.append(PointLightComponent())


class TextRenderActor(Actor):
    def __init__(self, location, rotation):
        super().__init__(location, rotation)
        self.components.append(TextRenderComponent())


class EditorActorSubsystem:
    def __init__(self):
        self.actors = []

    def spawn_actor_from_class(self, actor_class, location, rotation=None):
        actor = actor_class(location, rotation or Rotator())
        self.actors.append(actor)
        return actor

    def get_all_level_actors(self):
        return list(self.actors)

    def destroy_actor(self, actor):
        self.actors.remove(actor)


_subsystems = {}
_assets = {}


def get_editor_subsystem(subsystem_class):
    if subsystem_class not in _subsystems:
        _subsystems[subsystem_class] = subsystem_class()
    return _subsystems[subsystem_class]


def load_asset(path):
    if path not in _assets:
        _assets[path] = (StaticMesh if "/BasicShapes/" in path and "Material" not in path else Material)(path)
    return _assets[path]


class EditorAssetLibrary:
    @staticmethod
    def does_asset_exist(path):
        return path in _assets

    @staticmethod
    def load_asset(path):
        return _assets[path]


class _AssetTools:
    def create_asset(self, name, folder, asset_class, factory):
        asset = asset_class(folder + "/" + name)
        _assets[folder + "/" + name] = asset
        return asset


class AssetToolsHelpers:
    @staticmethod
    def get_asset_tools():
        return _AssetTools()


class MaterialEditingLibrary:
    @staticmethod
    def set_material_instance_parent(instance, parent):
        instance.parent = parent

    @staticmethod
    def set_material_instance_vector_parameter_value(instance, name, value):
        instance.vectors[name] = value
        return True

    @staticmethod
    def get_material_instance_vector_parameter_value(instance, name):
        return instance.vectors[name]


class ScopedSlowTask:
    def __init__(self, work, text=""):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def make_dialog(self, can_cancel=False):
        pass

    def should_cancel(self):
        return False

    def enter_progress_frame(self, work=1):
        pass


LOG: list[str] = []


def log(text):
    LOG.append(str(text))


def log_warning(text):
    LOG.append("WARNING " + str(text))
