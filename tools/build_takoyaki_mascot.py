import json
import struct
import math

class GLTFBuilder:
    def __init__(self):
        self.materials = []
        self.meshes = []
        self.nodes = []
        self.buffer_data = bytearray()
        self.buffer_views = []
        self.accessors = []

    def add_material(self, name, base_color, metallic=0.0, roughness=0.5, double_sided=False, emissive=None):
        mat = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": base_color,
                "metallicFactor": float(metallic),
                "roughnessFactor": float(roughness)
            },
            "doubleSided": double_sided
        }
        if emissive:
            mat["emissiveFactor"] = emissive
        self.materials.append(mat)
        return len(self.materials) - 1

    def _add_buffer_view(self, data, target=None):
        offset = len(self.buffer_data)
        # 4-byte align
        pad = (4 - (offset % 4)) % 4
        if pad > 0:
            self.buffer_data.extend(b'\x00' * pad)
            offset += pad
        
        self.buffer_data.extend(data)
        bv = {
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": len(data)
        }
        if target:
            bv["target"] = target
        self.buffer_views.append(bv)
        return len(self.buffer_views) - 1

    def add_geometry(self, name, vertices, normals, uvs, indices, material_idx):
        # Pack vertices
        min_v = [min(v[i] for v in vertices) for i in range(3)]
        max_v = [max(v[i] for v in vertices) for i in range(3)]
        
        v_data = bytearray()
        for v in vertices:
            v_data.extend(struct.pack("<3f", v[0], v[1], v[2]))
        bv_pos = self._add_buffer_view(v_data, target=34962) # ARRAY_BUFFER
        acc_pos = len(self.accessors)
        self.accessors.append({
            "bufferView": bv_pos,
            "byteOffset": 0,
            "componentType": 5126, # FLOAT
            "count": len(vertices),
            "type": "VEC3",
            "min": min_v,
            "max": max_v
        })

        # Pack normals
        n_data = bytearray()
        for n in normals:
            n_data.extend(struct.pack("<3f", n[0], n[1], n[2]))
        bv_norm = self._add_buffer_view(n_data, target=34962)
        acc_norm = len(self.accessors)
        self.accessors.append({
            "bufferView": bv_norm,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(normals),
            "type": "VEC3"
        })

        # Pack uvs
        uv_data = bytearray()
        for uv in uvs:
            uv_data.extend(struct.pack("<2f", uv[0], uv[1]))
        bv_uv = self._add_buffer_view(uv_data, target=34962)
        acc_uv = len(self.accessors)
        self.accessors.append({
            "bufferView": bv_uv,
            "byteOffset": 0,
            "componentType": 5126,
            "count": len(uvs),
            "type": "VEC2"
        })

        # Pack indices
        idx_data = bytearray()
        for idx in indices:
            idx_data.extend(struct.pack("<H", idx))
        bv_idx = self._add_buffer_view(idx_data, target=34963) # ELEMENT_ARRAY_BUFFER
        acc_idx = len(self.accessors)
        self.accessors.append({
            "bufferView": bv_idx,
            "byteOffset": 0,
            "componentType": 5123, # UNSIGNED_SHORT
            "count": len(indices),
            "type": "SCALAR"
        })

        mesh_idx = len(self.meshes)
        self.meshes.append({
            "name": name,
            "primitives": [{
                "attributes": {
                    "POSITION": acc_pos,
                    "NORMAL": acc_norm,
                    "TEXCOORD_0": acc_uv
                },
                "indices": acc_idx,
                "material": material_idx,
                "mode": 4 # TRIANGLES
            }]
        })

        node_idx = len(self.nodes)
        self.nodes.append({
            "name": name,
            "mesh": mesh_idx
        })
        return node_idx

    def build_glb(self, output_path):
        # 4-byte align the buffer data
        pad = (4 - (len(self.buffer_data) % 4)) % 4
        if pad > 0:
            self.buffer_data.extend(b'\x00' * pad)

        gltf = {
            "asset": {"version": "2.0", "generator": "T3 Takoyaki Mascot Generator"},
            "scene": 0,
            "scenes": [{"name": "DefaultScene", "nodes": list(range(len(self.nodes)))}],
            "nodes": self.nodes,
            "meshes": self.meshes,
            "materials": self.materials,
            "buffers": [{"byteLength": len(self.buffer_data)}],
            "bufferViews": self.buffer_views,
            "accessors": self.accessors
        }

        json_bytes = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
        json_pad = (4 - (len(json_bytes) % 4)) % 4
        if json_pad > 0:
            json_bytes += b' ' * json_pad

        total_length = 12 + 8 + len(json_bytes) + 8 + len(self.buffer_data)
        header = struct.pack("<4sII", b"glTF", 2, total_length)
        chunk0_hdr = struct.pack("<II", len(json_bytes), 0x4E4F534A) # JSON
        chunk1_hdr = struct.pack("<II", len(self.buffer_data), 0x004E4942) # BIN

        with open(output_path, "wb") as f:
            f.write(header)
            f.write(chunk0_hdr)
            f.write(json_bytes)
            f.write(chunk1_hdr)
            f.write(self.buffer_data)
        print(f"GLB written to {output_path} ({total_length} bytes)")

def create_sphere(center, rx, ry, rz, stacks=24, slices=24):
    vertices, normals, uvs, indices = [], [], [], []
    cx, cy, cz = center
    for i in range(stacks + 1):
        phi = math.pi * i / stacks
        y = cy + ry * math.cos(phi)
        r_slice = math.sin(phi)
        for j in range(slices + 1):
            theta = 2.0 * math.pi * j / slices
            x = cx + rx * r_slice * math.sin(theta)
            z = cz + rz * r_slice * math.cos(theta)
            vertices.append([x, y, z])
            
            # Normal calculation for ellipsoid
            nx = (x - cx) / (rx * rx)
            ny = (y - cy) / (ry * ry)
            nz = (z - cz) / (rz * rz)
            l = math.sqrt(nx*nx + ny*ny + nz*nz) or 1.0
            normals.append([nx/l, ny/l, nz/l])
            uvs.append([j / slices, i / stacks])
            
    for i in range(stacks):
        for j in range(slices):
            first = i * (slices + 1) + j
            second = first + slices + 1
            indices.extend([first, second, first + 1])
            indices.extend([second, second + 1, first + 1])
    return vertices, normals, uvs, indices

def create_torus(center, r_major, r_minor, tilt_deg=0, axis=(1,0,0), stacks=20, slices=20):
    vertices, normals, uvs, indices = [], [], [], []
    cx, cy, cz = center
    tilt = math.radians(tilt_deg)
    cos_t, sin_t = math.cos(tilt), math.sin(tilt)
    
    for i in range(stacks + 1):
        phi = 2.0 * math.pi * i / stacks
        cos_p, sin_p = math.cos(phi), math.sin(phi)
        for j in range(slices + 1):
            theta = 2.0 * math.pi * j / slices
            cos_th, sin_th = math.cos(theta), math.sin(theta)
            
            # Local torus coordinates
            lx = (r_major + r_minor * math.cos(theta)) * math.cos(phi)
            ly = r_minor * math.sin(theta)
            lz = (r_major + r_minor * math.cos(theta)) * math.sin(phi)
            
            # Apply tilt around X axis
            wx = lx
            wy = ly * cos_t - lz * sin_t
            wz = ly * sin_t + lz * cos_t
            
            vertices.append([cx + wx, cy + wy, cz + wz])
            
            lnx = math.cos(theta) * math.cos(phi)
            lny = math.sin(theta)
            lnz = math.cos(theta) * math.sin(phi)
            wnx = lnx
            wny = lny * cos_t - lnz * sin_t
            wnz = lny * sin_t + lnz * cos_t
            normals.append([wnx, wny, wnz])
            uvs.append([i / stacks, j / slices])
            
    for i in range(stacks):
        for j in range(slices):
            first = i * (slices + 1) + j
            second = first + slices + 1
            indices.extend([first, second, first + 1])
            indices.extend([second, second + 1, first + 1])
    return vertices, normals, uvs, indices

def create_tentacle(base_pos, outward_angle, length=0.026, root_r=0.010, tip_r=0.0035, segments=12, rings=10):
    vertices, normals, uvs, indices = [], [], [], []
    bx, by, bz = base_pos
    
    # Path of tentacle in 3D:
    # Starts at base, extends radially outward, curves down to floor, tip curls up slightly
    cos_a, sin_a = math.cos(outward_angle), math.sin(outward_angle)
    # Perp vector in horizontal plane
    perp_x, perp_z = -sin_a, cos_a
    
    backbone = []
    frames = []
    
    for s in range(segments + 1):
        t = s / segments
        # Radial outward reach
        reach = length * (t * 0.9 + 0.1 * t * t)
        # Vertical profile: start at by, droop to ground (y ~ -0.020), curl up at tip
        y = by - 0.018 * math.sin(t * math.pi * 0.7) + 0.004 * (t**3)
        # Subtle horizontal wave/curl
        curl = 0.003 * math.sin(t * math.pi * 1.2)
        
        px = bx + reach * sin_a + curl * perp_x
        pz = bz + reach * cos_a + curl * perp_z
        backbone.append([px, y, pz])
        
    for s in range(segments + 1):
        t = s / segments
        p = backbone[s]
        # Tangent
        if s < segments:
            p_next = backbone[s+1]
            tangent = [p_next[0] - p[0], p_next[1] - p[1], p_next[2] - p[2]]
        else:
            p_prev = backbone[s-1]
            tangent = [p[0] - p_prev[0], p[1] - p_prev[1], p[2] - p_prev[2]]
        tl = math.sqrt(sum(x*x for x in tangent)) or 1.0
        tangent = [x / tl for x in tangent]
        
        # Up vector
        up = [0.0, 1.0, 0.0]
        # Side vector = tangent x up
        side = [tangent[1]*up[2] - tangent[2]*up[1],
                tangent[2]*up[0] - tangent[0]*up[2],
                tangent[0]*up[1] - tangent[1]*up[0]]
        sl = math.sqrt(sum(x*x for x in side)) or 1.0
        side = [x / sl for x in side]
        # Recomputed normal = side x tangent
        norm = [side[1]*tangent[2] - side[2]*tangent[1],
                side[2]*tangent[0] - side[0]*tangent[2],
                side[0]*tangent[1] - side[1]*tangent[0]]
        
        # Radius tapers
        r = root_r * (1.0 - t * 0.65)
        if s == segments:
            r = tip_r
            
        for r_i in range(rings + 1):
            theta = 2.0 * math.pi * r_i / rings
            cos_th, sin_th = math.cos(theta), math.sin(theta)
            
            vx = p[0] + (side[0] * cos_th + norm[0] * sin_th) * r
            vy = p[1] + (side[1] * cos_th + norm[1] * sin_th) * r
            vz = p[2] + (side[2] * cos_th + norm[2] * sin_th) * r
            vertices.append([vx, vy, vz])
            
            nx = side[0] * cos_th + norm[0] * sin_th
            ny = side[1] * cos_th + norm[1] * sin_th
            nz = side[2] * cos_th + norm[2] * sin_th
            normals.append([nx, ny, nz])
            uvs.append([t, r_i / rings])
            
    for s in range(segments):
        for r_i in range(rings):
            first = s * (rings + 1) + r_i
            second = first + rings + 1
            indices.extend([first, second, first + 1])
            indices.extend([second, second + 1, first + 1])
            
    return vertices, normals, uvs, indices

def create_suction_cup(pos, normal, radius=0.0022):
    # Small flattened hemispherical cup on tentacle underside
    px, py, pz = pos
    nx, ny, nz = normal
    # Helper coordinate frame
    up = [0, 1, 0] if abs(ny) < 0.9 else [1, 0, 0]
    side = [ny*up[2] - nz*up[1], nz*up[0] - nx*up[2], nx*up[1] - ny*up[0]]
    sl = math.sqrt(sum(x*x for x in side)) or 1.0
    side = [x / sl for x in side]
    fwd = [side[1]*nz - side[2]*ny, side[2]*nx - side[0]*nz, side[0]*ny - side[1]*nx]
    
    vertices, normals, uvs, indices = [], [], [], []
    stacks, slices = 6, 10
    for i in range(stacks + 1):
        phi = (math.pi * 0.5) * i / stacks
        h = radius * 0.6 * math.cos(phi)
        r = radius * math.sin(phi)
        for j in range(slices + 1):
            theta = 2.0 * math.pi * j / slices
            ct, st = math.cos(theta), math.sin(theta)
            vx = px + side[0]*r*ct + fwd[0]*r*st + nx*h
            vy = py + side[1]*r*ct + fwd[1]*r*st + ny*h
            vz = pz + side[2]*r*ct + fwd[2]*r*st + nz*h
            vertices.append([vx, vy, vz])
            
            # Normal
            lnx = side[0]*ct*0.5 + fwd[0]*st*0.5 + nx*0.8
            lny = side[1]*ct*0.5 + fwd[1]*st*0.5 + ny*0.8
            lnz = side[2]*ct*0.5 + fwd[2]*st*0.5 + nz*0.8
            l = math.sqrt(lnx*lnx + lny*lny + lnz*lnz) or 1.0
            normals.append([lnx/l, lny/l, lnz/l])
            uvs.append([j / slices, i / stacks])
            
    for i in range(stacks):
        for j in range(slices):
            first = i * (slices + 1) + j
            second = first + slices + 1
            indices.extend([first, second, first + 1])
            indices.extend([second, second + 1, first + 1])
    return vertices, normals, uvs, indices

def build_takoyaki_mascot(glb_path):
    builder = GLTFBuilder()
    
    # 1. PBR Materials
    # Vibrant warm coral red skin for Takoyaki mascot
    mat_tako = builder.add_material("M_TakoSkin", [0.933, 0.302, 0.239, 1.0], metallic=0.04, roughness=0.32, emissive=[0.18, 0.06, 0.05])
    # Soft cream white for suction cups
    mat_cream = builder.add_material("M_SuctionCups", [0.988, 0.941, 0.886, 1.0], metallic=0.0, roughness=0.45, emissive=[0.22, 0.20, 0.18])
    # Pouty mouth lips
    mat_mouth_lip = builder.add_material("M_MouthLips", [0.980, 0.420, 0.360, 1.0], metallic=0.02, roughness=0.30, emissive=[0.20, 0.08, 0.07])
    # Deep mouth shadow
    mat_mouth_in = builder.add_material("M_MouthIn", [0.220, 0.040, 0.050, 1.0], metallic=0.0, roughness=0.90)
    # Glossy obsidian anime pupil
    mat_pupil = builder.add_material("M_EyePupil", [0.070, 0.075, 0.100, 1.0], metallic=0.1, roughness=0.08)
    # Pure white glossy eye sparkle
    mat_spark = builder.add_material("M_EyeSparkle", [1.0, 1.0, 1.0, 1.0], metallic=0.0, roughness=0.05, emissive=[1.0, 1.0, 1.0])
    # Sweet sakura rosy blush
    mat_blush = builder.add_material("M_Blush", [1.0, 0.470, 0.580, 1.0], metallic=0.0, roughness=0.65, emissive=[0.35, 0.12, 0.18])
    # Japanese festive headband (crisp cotton white)
    mat_headband = builder.add_material("M_Headband", [0.960, 0.965, 0.975, 1.0], metallic=0.02, roughness=0.55, emissive=[0.25, 0.25, 0.26])
    # Polished golden bell
    mat_bell = builder.add_material("M_GoldenBell", [1.0, 0.780, 0.160, 1.0], metallic=0.88, roughness=0.18, emissive=[0.25, 0.18, 0.04])
    
    # 2. Main Mantle (Chubby squat sphere)
    v, n, uv, idx = create_sphere([0.0, 0.024, 0.0], rx=0.038, ry=0.033, rz=0.036, stacks=24, slices=28)
    builder.add_geometry("Mantle", v, n, uv, idx, mat_tako)
    
    # 3. 8 Integrated Chubby Curly Tentacle Feet
    # Spaced around the bottom circumference of the mantle
    for arm_i in range(8):
        # Angle around mantle: arm 0 is slightly to the right, arms wrap around
        theta = (2.0 * math.pi * arm_i / 8.0) + (math.pi / 8.0)
        # Base starts at lower mantle edge
        root_r = 0.030
        bx = root_r * math.sin(theta)
        bz = root_r * math.cos(theta)
        by = 0.003 # low mantle height
        
        v_tent, n_tent, uv_tent, idx_tent = create_tentacle(
            [bx, by, bz], outward_angle=theta, length=0.026, root_r=0.009, tip_r=0.0035, segments=10, rings=8
        )
        builder.add_geometry(f"Tentacle_{arm_i}", v_tent, n_tent, uv_tent, idx_tent, mat_tako)
        
        # Add 2 cute suction cups under each tentacle foot
        for cup_i, dist in enumerate([0.38, 0.68]):
            # Position along tentacle
            reach = 0.026 * dist
            curl = 0.003 * math.sin(dist * math.pi * 1.2)
            perp_x, perp_z = -math.cos(theta), math.sin(theta)
            cx = bx + reach * math.sin(theta) + curl * perp_x
            cz = bz + reach * math.cos(theta) + curl * perp_z
            cy = by - 0.016 * math.sin(dist * math.pi * 0.7) - 0.002
            v_cup, n_cup, uv_cup, idx_cup = create_suction_cup([cx, cy, cz], [0.0, -1.0, 0.0], radius=0.0020)
            builder.add_geometry(f"SuctionCup_{arm_i}_{cup_i}", v_cup, n_cup, uv_cup, idx_cup, mat_cream)

    # 4. Pouty Siphon / Mouth (嘟嘟嘴)
    v_mouth, n_mouth, uv_mouth, idx_mouth = create_torus(
        [0.0, 0.015, -0.035], r_major=0.0055, r_minor=0.0028, tilt_deg=-12, stacks=14, slices=14
    )
    builder.add_geometry("MouthLips", v_mouth, n_mouth, uv_mouth, idx_mouth, mat_mouth_lip)
    
    v_min, n_min, uv_min, idx_min = create_sphere([0.0, 0.015, -0.034], rx=0.0042, ry=0.0042, rz=0.0025, stacks=10, slices=12)
    builder.add_geometry("MouthInterior", v_min, n_min, uv_min, idx_min, mat_mouth_in)
    
    # 5. Anime Sparkly Eyes
    eye_x = 0.020
    eye_y = 0.024
    eye_z = -0.032
    
    # Left eye
    v_el, n_el, uv_el, idx_el = create_sphere([eye_x, eye_y, eye_z], rx=0.0068, ry=0.0078, rz=0.0038, stacks=14, slices=16)
    builder.add_geometry("EyePupil_Left", v_el, n_el, uv_el, idx_el, mat_pupil)
    # Left sparkles
    v_s1, n_s1, uv_s1, idx_s1 = create_sphere([eye_x + 0.0020, eye_y + 0.0025, eye_z - 0.0032], rx=0.0022, ry=0.0022, rz=0.0012, stacks=8, slices=10)
    builder.add_geometry("EyeSpark1_Left", v_s1, n_s1, uv_s1, idx_s1, mat_spark)
    v_s2, n_s2, uv_s2, idx_s2 = create_sphere([eye_x - 0.0022, eye_y - 0.0024, eye_z - 0.0030], rx=0.0012, ry=0.0012, rz=0.0008, stacks=6, slices=8)
    builder.add_geometry("EyeSpark2_Left", v_s2, n_s2, uv_s2, idx_s2, mat_spark)
    # Left blush
    v_bl, n_bl, uv_bl, idx_bl = create_sphere([eye_x + 0.009, eye_y - 0.009, eye_z + 0.005], rx=0.0050, ry=0.0026, rz=0.0020, stacks=8, slices=10)
    builder.add_geometry("Blush_Left", v_bl, n_bl, uv_bl, idx_bl, mat_blush)

    # Right eye
    v_er, n_er, uv_er, idx_er = create_sphere([-eye_x, eye_y, eye_z], rx=0.0068, ry=0.0078, rz=0.0038, stacks=14, slices=16)
    builder.add_geometry("EyePupil_Right", v_er, n_er, uv_er, idx_er, mat_pupil)
    # Right sparkles
    v_sr1, n_sr1, uv_sr1, idx_sr1 = create_sphere([-eye_x - 0.0020, eye_y + 0.0025, eye_z - 0.0032], rx=0.0022, ry=0.0022, rz=0.0012, stacks=8, slices=10)
    builder.add_geometry("EyeSpark1_Right", v_sr1, n_sr1, uv_sr1, idx_sr1, mat_spark)
    v_sr2, n_sr2, uv_sr2, idx_sr2 = create_sphere([-eye_x + 0.0022, eye_y - 0.0024, eye_z - 0.0030], rx=0.0012, ry=0.0012, rz=0.0008, stacks=6, slices=8)
    builder.add_geometry("EyeSpark2_Right", v_sr2, n_sr2, uv_sr2, idx_sr2, mat_spark)
    # Right blush
    v_br, n_br, uv_br, idx_br = create_sphere([-eye_x - 0.009, eye_y - 0.009, eye_z + 0.005], rx=0.0050, ry=0.0026, rz=0.0020, stacks=8, slices=10)
    builder.add_geometry("Blush_Right", v_br, n_br, uv_br, idx_br, mat_blush)

    # 6. Japanese Festive Hachimaki Headband
    v_hb, n_hb, uv_hb, idx_hb = create_torus([0.0, 0.038, -0.003], r_major=0.0365, r_minor=0.0032, tilt_deg=-15, stacks=24, slices=14)
    builder.add_geometry("Headband", v_hb, n_hb, uv_hb, idx_hb, mat_headband)
    
    # Knot fold on right temple
    v_k1, n_k1, uv_k1, idx_k1 = create_sphere([0.033, 0.042, -0.010], rx=0.0050, ry=0.0035, rz=0.0035, stacks=10, slices=10)
    builder.add_geometry("BowFold1", v_k1, n_k1, uv_k1, idx_k1, mat_headband)
    v_k2, n_k2, uv_k2, idx_k2 = create_sphere([0.036, 0.046, -0.008], rx=0.0038, ry=0.0060, rz=0.0028, stacks=10, slices=10)
    builder.add_geometry("BowFold2", v_k2, n_k2, uv_k2, idx_k2, mat_headband)

    # 7. Lucky Golden Bell
    bell_pos = [0.036, 0.034, -0.014]
    v_bell, n_bell, uv_bell, idx_bell = create_sphere(bell_pos, rx=0.0052, ry=0.0052, rz=0.0052, stacks=16, slices=16)
    builder.add_geometry("GoldenBell", v_bell, n_bell, uv_bell, idx_bell, mat_bell)
    # Bell groove ring
    v_bg, n_bg, uv_bg, idx_bg = create_torus(bell_pos, r_major=0.0052, r_minor=0.0007, tilt_deg=0, stacks=14, slices=8)
    builder.add_geometry("BellGroove", v_bg, n_bg, uv_bg, idx_bg, mat_bell)

    builder.build_glb(glb_path)

if __name__ == "__main__":
    build_takoyaki_mascot("assets/models/octopus/takoyaki_mascot.glb")
