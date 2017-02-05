use std;
use simd::types::*;

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct float3x4(pub float4, pub float4, pub float4);
pub type matrix_float3x4 = float3x4;

impl std::ops::Add for float3x4 {
  type Output = Self;

  #[inline]
  fn add(self, other: Self) -> Self {
    return float3x4(self.0.add(other.0), self.1.add(other.1), self.2.add(other.2));
  }
}

impl std::ops::Add<f32> for float3x4 {
  type Output = Self;

  #[inline]
  fn add(self, other: f32) -> Self {
    let other = float4::broadcast(other);

    return float3x4(self.0.add(other), self.1.add(other), self.2.add(other));
  }
}

impl std::ops::Add<float3x4> for f32 {
  type Output = float3x4;

  #[inline]
  fn add(self, other: float3x4) -> float3x4 {
    let scalar = float4::broadcast(self);

    return float3x4(scalar.add(other.0), scalar.add(other.1), scalar.add(other.2));
  }
}

impl std::ops::Sub for float3x4 {
  type Output = Self;

  #[inline]
  fn sub(self, other: Self) -> Self {
    return float3x4(self.0.sub(other.0), self.1.sub(other.1), self.2.sub(other.2));
  }
}

impl std::ops::Sub<f32> for float3x4 {
  type Output = Self;

  #[inline]
  fn sub(self, other: f32) -> Self {
    let other = float4::broadcast(other);

    return float3x4(self.0.sub(other), self.1.sub(other), self.2.sub(other));
  }
}

impl std::ops::Sub<float3x4> for f32 {
  type Output = float3x4;

  #[inline]
  fn sub(self, other: float3x4) -> float3x4 {
    let scalar = float4::broadcast(self);

    return float3x4(scalar.sub(other.0), scalar.sub(other.1), scalar.sub(other.2));
  }
}

impl std::ops::Mul for float3x4 {
  type Output = Self;

  #[inline]
  fn mul(self, other: Self) -> Self {
    return float3x4(self.0.mul(other.0), self.1.mul(other.1), self.2.mul(other.2));
  }
}

impl std::ops::Mul<f32> for float3x4 {
  type Output = Self;

  #[inline]
  fn mul(self, other: f32) -> Self {
    let other = float4::broadcast(other);

    return float3x4(self.0.mul(other), self.1.mul(other), self.2.mul(other));
  }
}

impl std::ops::Mul<float3x4> for f32 {
  type Output = float3x4;

  #[inline]
  fn mul(self, other: float3x4) -> float3x4 {
    let scalar = float4::broadcast(self);

    return float3x4(scalar.mul(other.0), scalar.mul(other.1), scalar.mul(other.2));
  }
}

impl std::ops::Div for float3x4 {
  type Output = Self;

  #[inline]
  fn div(self, other: Self) -> Self {
    return float3x4(self.0.div(other.0), self.1.div(other.1), self.2.div(other.2));
  }
}

impl std::ops::Div<f32> for float3x4 {
  type Output = Self;

  #[inline]
  fn div(self, other: f32) -> Self {
    let other = float4::broadcast(other);

    return float3x4(self.0.div(other), self.1.div(other), self.2.div(other));
  }
}

impl std::ops::Div<float3x4> for f32 {
  type Output = float3x4;

  #[inline]
  fn div(self, other: float3x4) -> float3x4 {
    let scalar = float4::broadcast(self);

    return float3x4(scalar.div(other.0), scalar.div(other.1), scalar.div(other.2));
  }
}