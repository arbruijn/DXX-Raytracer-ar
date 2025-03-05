#include "include/common.hlsl"

struct OcclusionRayPayload
{
	bool visible;
	float hit_distance;
	uint primitive_idx;
	int invalid_primitive_hit;						// what invalid primitive id was hit (so we can ignore it when we try again)
	int hit_segment;                           // what level segment (if any) does the hit belong to.  Could look this up with instance and primitive idx's, but simpler to just record it here.
};

void TraceOcclusionRay(RayDesc ray, inout OcclusionRayPayload payload, uint2 pixel_pos)
{
#if RT_DISPATCH_RAYS

    TraceRay(g_scene, RAY_FLAG_CULL_BACK_FACING_TRIANGLES | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,
        ~2, 1, 0, 1, ray, payload);

#elif RT_INLINE_RAYTRACING

    RayQuery<RAY_FLAG_CULL_BACK_FACING_TRIANGLES> ray_query;
	ray_query.TraceRayInline(
		g_scene,
		RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
		~2,
		ray
	);

	while (ray_query.Proceed())
	{
		switch (ray_query.CandidateType())
		{
			case CANDIDATE_NON_OPAQUE_TRIANGLE:
			{
				uint instance_idx = ray_query.CandidateInstanceIndex();
				uint primitive_idx = ray_query.CandidatePrimitiveIndex();

				InstanceData instance_data = g_instance_data_buffer[instance_idx];
				RT_Triangle hit_triangle = GetHitTriangle(instance_data.triangle_buffer_idx, primitive_idx);

				Material hit_material;

				if (payload.invalid_primitive_hit != primitive_idx) // ignore invalid primitive
				{
					if (!IsHitTransparent(
						ray_query.CandidateInstanceIndex(),
						ray_query.CandidatePrimitiveIndex(),
						ray_query.CandidateTriangleBarycentrics(),
						pixel_pos,
						hit_material
					))
					{
						ray_query.CommitNonOpaqueTriangleHit();
					}
				}
				break;
			}
		}
	}

	switch (ray_query.CommittedStatus())
	{
		case COMMITTED_TRIANGLE_HIT:
		{
			float hit_distance = ray_query.CommittedRayT();

			uint instance_idx = ray_query.CommittedInstanceIndex();
			uint primitive_idx = ray_query.CommittedPrimitiveIndex();

			InstanceData instance_data = g_instance_data_buffer[instance_idx];
			RT_Triangle hit_triangle = GetHitTriangle(instance_data.triangle_buffer_idx, primitive_idx);
		
			payload.visible = false;

			payload.hit_distance = hit_distance;
			payload.hit_segment = hit_triangle.segment;
			payload.primitive_idx = primitive_idx;
		
			break;
		}
		case COMMITTED_NOTHING:
		{
			payload.visible = true;
			break;
		}
	}

#endif
}

[shader("anyhit")]
void OcclusionAnyhit(inout OcclusionRayPayload payload, in BuiltInTriangleIntersectionAttributes attr)
{
    Material hit_material;
    if (IsHitTransparent(InstanceIndex(), PrimitiveIndex(), attr.barycentrics, DispatchRaysIndex().xy, hit_material))
    {
        IgnoreHit();
    }

    if (hit_material.flags & RT_MaterialFlag_NoCastingShadow)
    {
        IgnoreHit();
    }
}

[shader("miss")]
void OcclusionMiss(inout OcclusionRayPayload payload)
{
    payload.visible = true;
}
