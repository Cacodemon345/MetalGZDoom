
#include "ml_renderstate.h"
#include "metal/system/ml_framebuffer.h"
#include "metal/system/ml_buffer.h"
#include "metal/renderer/ml_streambuffer.h"

namespace MetalRenderer
{

MlStreamBuffer::MlStreamBuffer(size_t structSize, size_t count)
{
	mBlockSize = static_cast<uint32_t>((structSize + screen->uniformblockalignment - 1) / screen->uniformblockalignment * screen->uniformblockalignment);

	UniformBuffer = (MlDataBuffer*)GetMetalFrameBuffer()->CreateDataBuffer(-1, false, false);
	UniformBuffer->SetData(mBlockSize * count, nullptr, false);
}

MlStreamBuffer::~MlStreamBuffer()
{
	delete UniformBuffer;
}

uint32_t MlStreamBuffer::NextStreamDataBlock()
{
	mStreamDataOffset += mBlockSize;
	if (mStreamDataOffset + (size_t)mBlockSize >= UniformBuffer->Size())
	{
		mStreamDataOffset = 0;
		return 0xffffffff;
	}
	return mStreamDataOffset;
}

/////////////////////////////////////////////////////////////////////////////

MlStreamBufferWriter::MlStreamBufferWriter()
{
	mBuffer = GetMetalFrameBuffer()->StreamBuffer;
}

bool MlStreamBufferWriter::Write(const StreamData& data)
{
	mDataIndex++;
	if (mDataIndex == 255)
	{
		mDataIndex = 0;
		mStreamDataOffset = mBuffer->NextStreamDataBlock();
		if (mStreamDataOffset == 0xffffffff)
			return false;
	}
	uint8_t* ptr = (uint8_t*)mBuffer->UniformBuffer->Memory();
	memcpy(ptr + mStreamDataOffset + sizeof(StreamData) * mDataIndex, &data, sizeof(StreamData));
	return true;
}

void MlStreamBufferWriter::Reset()
{
	//mDataIndex = MAX_STREAM_DATA - 1;
	//mStreamDataOffset = 0;
	//mBuffer->Reset();
}

/////////////////////////////////////////////////////////////////////////////

MlMatrixBufferWriter::MlMatrixBufferWriter()
{
	mBuffer = GetMetalFrameBuffer()->MatrixBuffer;
	mIdentityMatrix.loadIdentity();
}

template<typename T>
static void BufferedSet(bool& modified, T& dst, const T& src)
{
	if (dst == src)
		return;
	dst = src;
	modified = true;
}

static void BufferedSet(bool& modified, VSMatrix& dst, const VSMatrix& src)
{
	if (memcmp(dst.get(), src.get(), sizeof(FLOATTYPE) * 16) == 0)
		return;
	dst = src;
	modified = true;
}

bool MlMatrixBufferWriter::Write(const VSMatrix& modelMatrix, bool modelMatrixEnabled, const VSMatrix& textureMatrix, bool textureMatrixEnabled)
{
	bool modified = (mOffset == 0); // always modified first call

	if (modelMatrixEnabled)
	{
		BufferedSet(modified, mMatrices.ModelMatrix, modelMatrix);
		if (modified)
			mMatrices.NormalModelMatrix.computeNormalMatrix(modelMatrix);
	}
	else
	{
		BufferedSet(modified, mMatrices.ModelMatrix, mIdentityMatrix);
		BufferedSet(modified, mMatrices.NormalModelMatrix, mIdentityMatrix);
	}

	if (textureMatrixEnabled)
	{
		BufferedSet(modified, mMatrices.TextureMatrix, textureMatrix);
	}
	else
	{
		BufferedSet(modified, mMatrices.TextureMatrix, mIdentityMatrix);
	}

	if (modified)
	{
		mOffset = mBuffer->NextStreamDataBlock();
		if (mOffset == 0xffffffff)
			return false;

		uint8_t* ptr = (uint8_t*)mBuffer->UniformBuffer->Memory();
		memcpy(ptr + mOffset, &mMatrices, sizeof(MatricesUBO));
	}

	return true;
}

void MlMatrixBufferWriter::Reset()
{
	mOffset = 0;
	mBuffer->Reset();
}

}
