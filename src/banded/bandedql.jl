
ql!(A::BandedMatrix) = banded_ql!(A)

ql(A::BandedMatrix) = banded_ql!(BandedMatrix(A, (bandwidth(A,1)+bandwidth(A,2),bandwidth(A,2))))
ql(A::Tridiagonal) = banded_ql!(BandedMatrix(A, (2,1)))

function banded_ql!(L::BandedMatrix{T}) where T
    D = bandeddata(L)
    l,u = bandwidths(L)
    ν = l+u+1
    m,n=size(L)
    τ = zeros(T, min(m,n))

    for k = min(m, n):-1:(1 + (T<:Real))
        x = view(D,u+1:-1:max(1,u-k+2), k)
        τk = reflector!(x)
        τ[k] = τk
        N = length(x)
        for j = k-1:-1:max(1,k-l)
            reflectorApply!(x, τk, view(D, u+1+k-j:-1:u+2+k-j-N,j:j))
        end
    end
    QL(L, τ)
end

function lmul!(adjA::Adjoint{<:Any,<:QLPackedQ{<:Any,<:BandedMatrix}}, B::AbstractVecOrMat)
    @assert !has_offset_axes(B)
    A = adjA.parent
    mA, nA = size(A.factors)
    mB, nB = size(B,1), size(B,2)
    if mA != mB
        throw(DimensionMismatch("matrix A has dimensions ($mA,$nA) but B has dimensions ($mB, $nB)"))
    end
    Afactors = A.factors
    l,u = bandwidths(Afactors)
    D = Afactors.data
    @inbounds begin
        for k = min(mA,nA):-1:1
            for j = 1:nB
                vBj = B[k,j]
                for i = max(1,k-u):k-1
                    vBj += conj(D[i-k+u+1,k])*B[i,j]
                end
                vBj = conj(A.τ[k])*vBj
                B[k,j] -= vBj
                for i = max(1,k-u):k-1
                    B[i,j] -= D[i-k+u+1,k]*vBj
                end
            end
        end
    end
    B
end

function _banded_widerect_ldiv!(A::QL, B)
    error("Not implemented")
end
function _banded_longrect_ldiv!(A::QL, B)
    error("Not implemented")
end
function _banded_square_ldiv!(A::QL, B)
    L = A.factors
    lmul!(adjoint(A.Q), B)
    B .= Ldiv(LowerTriangular(L), B)
    B
end

for Typ in (:StridedVector, :StridedMatrix, :AbstractVecOrMat) 
    @eval function ldiv!(A::QL{T,<:BandedMatrix}, B::$Typ{T}) where T
        m, n = size(A)
        if m == n
            _banded_square_ldiv!(A, B)
        elseif n > m
            _banded_widerect_ldiv!(A, B)
        else
            _banded_longrect_ldiv!(A, B)
        end
    end
end
