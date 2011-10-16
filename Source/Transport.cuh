/*
	Copyright (c) 2011, T. Kroes <t.kroes@tudelft.nl>
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	- Neither the name of the <ORGANIZATION> nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#pragma once

#include "Shader.cuh"
#include "RayMarching.cuh"

DEV CColorXyz EstimateDirectLightBrdf(CScene* pScene, const float& Density, CLight& Light, CLightingSample& LS, const Vec3f& Wo, const Vec3f& Pe, const Vec3f& N, CRNG& Rnd)
{
	CColorXyz Ld = SPEC_BLACK, Li = SPEC_BLACK, F = SPEC_BLACK;
	
	CBSDF Bsdf(N, Wo, GetDiffuse(Density).ToXYZ(), GetSpecular(Density).ToXYZ(), 5.5f/*pScene->m_IOR*/, GetRoughness(Density));
	
	// Light/shadow ray
	CRay Rl; 

	// Light probability
	float LightPdf = 1.0f, BsdfPdf = 1.0f;
	
	// Incident light direction
	Vec3f Wi, P, Pl;

	// Sample the light source
 	Li = Light.SampleL(Pe, Rl, LightPdf, LS);
	
	CLight* pLight = NULL;

	Wi = -Rl.m_D; 

	F = Bsdf.F(Wo, Wi); 

	BsdfPdf	= Bsdf.Pdf(Wo, Wi);

	// Sample the light with MIS
	if (!Li.IsBlack() && BsdfPdf > 0.0f && LightPdf > 0.0f && !FreePathRM(Rl, Rnd))
	{
		const float WeightMIS = PowerHeuristic(1.0f, LightPdf, 1.0f, BsdfPdf);
 
		Ld += F * Li * (AbsDot(Wi, N) * WeightMIS / LightPdf);
	}

	/*
	// Sample the BRDF with MIS
	F = Bsdf.SampleF(Wo, Wi, BsdfPdf, LS.m_BsdfSample);
	
	if (!F.IsBlack() && BsdfPdf > 0.0f)
	{
		float WeightMIS = 1.0f;

		LightPdf = Light.Pdf(Pe, Wi);

		if (LightPdf == 0.0f)
			return Ld;
		
		WeightMIS = PowerHeuristic(1.0f, BsdfPdf, 1.0f, LightPdf);

		if (NearestLight(pScene, CRay(Pe, Wi, 0.0f), Li, Pl, pLight, &LightPdf) && pLight == &Light)
		{
			if (!Li.IsBlack() && !FreePathRM(CRay(Pl, Normalize(Pe - Pl), 0.0f, (Pe - Pl).Length()), Rnd)) 
			{
				Ld += F * Li * AbsDot(Wi, N) * WeightMIS / BsdfPdf;
			}
		}
	}
	*/

	return Ld;
}

DEV CColorXyz EstimateDirectLightPhase(CScene* pScene, const float& Density, CLight& Light, CLightingSample& LS, const Vec3f& Wo, const Vec3f& Pe, const Vec3f& N, CRNG& Rnd)
{
	// Accumulated radiance
	CColorXyz Ld = SPEC_BLACK, Li = SPEC_BLACK, F = GetDiffuse(Density).ToXYZ();

	// Light/shadow ray
	CRay Rl; 

	// Light probability
	float LightPdf = 1.0f, PhasePdf = 1.0f;
	
	// Incident light direction
	Vec3f Wi, P, Pl;

	CLight* pLight = NULL;

	// Sample the light source
 	Li = Light.SampleL(Pe, Rl, LightPdf, LS);
	
	Wi = -Rl.m_D; 

	// Sample the light with MIS
	if (!Li.IsBlack() && LightPdf > 0.0f && !FreePathRM(Rl, Rnd))
	{
		const float WeightMIS = PowerHeuristic(1.0f, LightPdf, 1.0f, PhasePdf);

		Ld += F * Li * WeightMIS / LightPdf;
	}
	return Ld;
	PhasePdf = INV_4_PI_F;
	
	// Sample the phase function with MIS
	Wi = UniformSampleSphere(LS.m_BsdfSample.m_Dir);

	if (!F.IsBlack())
	{
		float WeightMIS = 1.0f;

		LightPdf = Light.Pdf(Pe, Wi);

		if (LightPdf == 0.0f)
			return Ld;

		WeightMIS = PowerHeuristic(1.0f, PhasePdf, 1.0f, LightPdf);

		if (NearestLight(pScene, CRay(Pe, Wi, 0.0f), Li, Pl, pLight, &LightPdf)/* && pLight == &Light*/)
		{
			if (!Li.IsBlack() && !FreePathRM(CRay(Pl, Normalize(Pe - Pl), 0.0f, (Pe - Pl).Length()), Rnd)) 
			{
				Ld += F * Li * WeightMIS / PhasePdf;
			}
		}
	}
	/**/

	return Ld;
}

DEV CColorXyz UniformSampleOneLight(CScene* pScene, const float& Density, const Vec3f& Wo, const Vec3f& Pe, const Vec3f& N, CRNG& Rnd, const bool& Brdf)
{
	// Determine no. lights
	const int NumLights = pScene->m_Lighting.m_NoLights;

	// Exit return zero radiance if no light
 	if (NumLights == 0)
 		return SPEC_BLACK;

	CLightingSample LS;

	// Create light sampler
	LS.LargeStep(Rnd);

	// Choose which light to sample
	const int WhichLight = (int)floorf(LS.m_LightNum * (float)NumLights);

	// Get the light
	CLight& Light = pScene->m_Lighting.m_Lights[WhichLight];

	if (Brdf)
		return (float)NumLights * EstimateDirectLightBrdf(pScene, Density, Light, LS, Wo, Pe, N, Rnd);
	else
		return (float)NumLights * EstimateDirectLightPhase(pScene, Density, Light, LS, Wo, Pe, N, Rnd);
}