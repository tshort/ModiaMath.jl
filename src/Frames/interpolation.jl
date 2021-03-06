# License for this file: MIT (expat)
# Copyright 2017-2018, DLR Institute of System Dynamics and Control
#
# This file is part of module
#   ModiaMath.Frames (ModiaMath/Frames/_module.jl)
#
const seps = sqrt(eps())


"""
    path = ModiaMath.Path(r::Vector{Vector3D},
                          q::Vector{Quaternion} = Quaternion[];
                          v = ones(length(r)))

Return an instance of a new Path object. The Path object consists of n frames
defined by the position vectors of their origins (`r[i]` for frame `i`) 
and optionally of their absolute rotation quaternions (`q[i]` for frame `i`)
describing the rotation from the world frame to the respective frame.

A path parameter `t` is defined in the following way on these frames:

- `t[1] = 0.0`.
- `t[i] = t[i-1] + pathLength_i/(v[i]+v[i-1])/2` if the origins of frames `i-1` and `i` do not coincide.
- `t[i] = t[i-1] + pathAngle_i/(v[i]+v[i-1])/2` if the origins of frames `i-1` and `i` do coincide.

Hereby `pathLength_i` is the distance between the origins of frames `i-1` and `i` in [m] and
`pathAngle_i` is the planar rotation angle between frames `i-1` and `i` in [rad].
 
If `v[i]` is the desired velocity or angular velocity at frame `i`, then path parameter
`t` is approximately the time to move along the path. The time instant `t_end` of the last frame can
be inquired with `ModiaMath.t_pathEnd(path)`. For example, if a simulation shall be performed in such 
a way that the simulation should start with the first frame and end at `stopTime` at the last frame,
then the path parameter should be selected as `t = time*t_end/stopTime`.

Given the actual path parameter, typically `0 <= t <= t_end` (if `t` is outside of this interval,
the frame at `t` is determined by extrapolation through the first two or the last two frames), 
the corresponding frame is determined by linear interpolation in the following way:

```julia
(rt, qt) = interpolate(  path,t)
 rt      = interpolate_r(path,t)
```

where `rt` is the position vector to the origin of the frame at path parameter `t`
and `qt` is the absolute quaternion of the frame at path parameter `t`.

# Example

```julia
import ModiaMath
using Unitful

r = [ ModiaMath.Vector3D(1,0,0),
      ModiaMath.Vector3D(0,1,0),
      ModiaMath.Vector3D(0,0,1) ]
q = [ ModiaMath.NullQuaternion,
      ModiaMath.qrot1(45u"°"),
      ModiaMath.qrot2(60u"°")]

path     = ModiaMath.Path(r,q)
t_end    = ModiaMath.t_pathEnd(path)
dt       = 0.1
stopTime = 2.0 
time     = 0.0

while time <= stopTime
   (rt, qt) = ModiaMath.interpolate(path, time*t_end/stopTime)
   time += dt
end
```
"""
struct Path
   t::Vector{Float64}        # path parameter; t=0 is (r[1],q[1])
   r::Vector{Vector3D}       # Position vectors from world frame to origin of Frames
   q::Vector{Quaternion}     # Quaternions describing rotation from world frame to Frames

   function Path(r::AbstractVector, q::AbstractVector = Quaternion[]; 
                 v::AbstractVector = ones(length(r)), 
                 seps = sqrt(eps()) )
      nframes = size(r,1)
      @assert(seps > 0.0)
      @assert(nframes > 1)
      @assert(length(v) == nframes)
      @assert(size(q,1) == 0 || size(q,1) == nframes)
      @assert(v[1]   >= 0.0)
      @assert(v[end] >= 0.0)
      for i in 2:length(v) - 1
         @assert(v[i] > 0.0)
      end
      vv = convert(Vector{Float64}, v)

      # Determine path length for every segment
      t = zeros(nframes)
      for i in 2:nframes
         slen = norm(r[i] - r[i-1])
         if slen > seps
            # Use distance between r[i] and r[i-1] as path parameter (in [m]), scale with vv
            t[i] = t[i-1] + slen/((vv[i]+vv[i-1])/2)
 
         elseif length(q) > 0
            # Use planar rotation angle between q[i] and q[i-1] as path parameter (in [rad])
            q_rel = relativeRotation(q[i-1], q[i])
            q4    =  q_rel[4]
            q4    = q4 >  1+seps ?  1.0 :  
                    q4 < -1-seps ? -1.0 : q4
            absAngle = 2*acos(q4)
            if absAngle < seps
               error("ModiaMath.Path(..): r[i] == r[i-1] and q[i] == q[i-1] (i = ", i, ").")
            end
            t[i] = t[i-1] + absAngle/((vv[i]+vv[i-1])/2)
            
         else
            error("ModiaMath.Path(..): r[i] == r[i-1] (i = ", i, ").")
         end
      end
      new(t, r, q)
   end
end


"""
    t_end = ModiaMath.t_pathEnd(path::[`ModiaMath.Path`](@ref))

Return the final path parameter `t`of the last frame in path
(path parameter of first frame = 0.0).
"""
t_pathEnd(path::Path)::Float64 = path.t[end]



function get_interval(path::Path, t::Number)
   # returns index i, such that path.t[i] <= t < path.t[i+1]

   tvec = path.t
   if t <= 0.0 
      return 1
   elseif t >= tvec[end]
      return length(tvec)-1
   end

   low  = 1
   high = length(tvec)
   mid  = round(Int, (low+high)/2)

   while t < tvec[mid] || t >= tvec[mid+1] 
       if t < tvec[mid]
          high = mid
       else
          low = mid
       end
       mid = round(Int, (low+high)/2, RoundDown)
   end

   return mid
end




"""
    (rt, qt) = ModiaMath.interpolate(path, t)

Return position `rt`and Quaternion `qt` of `path::`[`ModiaMath.Path`](@ref) at path parameter `t::Number`.
"""
function interpolate(path::Path, t::Number)
   i    = get_interval(path, t)
   tvec = path.t
   tt::Float64  = convert(Float64, t)
   fac::Float64 = (tt - tvec[i])/(tvec[i+1] - tvec[i])
   rt = path.r[i] + fac*(path.r[i+1] - path.r[i])
   qt = length(path.q) > 0 ? normalize( path.q[i] + fac*(path.q[i+1] - path.q[i]) ) : NulLQuaternion

   return (rt, qt)
end



"""
    rt = ModiaMath.interpolate_r(path, t)

Return position `r` of `path::`[`ModiaMath.Path`](@ref) at path parameter `t::Number`.
"""
function interpolate_r(path::Path, t::Number)::Vector3D
   i    = get_interval(path, t)
   tvec = path.t
   tt::Float64  = convert(Float64, t)
   fac::Float64 = (tt - tvec[i])/(tvec[i+1] - tvec[i])
   return path.r[i] + fac*(path.r[i+1] - path.r[i])
end
