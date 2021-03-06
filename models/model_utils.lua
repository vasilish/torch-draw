require('nn')

local model_utils = {}

function model_utils.clone_model(model, T)
  local clones = {}
  for t = 1, T do
    clones[t] = model:clone('weight', 'bias', 'gradWeight', 'gradBias')
  end

  return clones
end

function model_utils.create_shared_container(unrolled_model)
  local sharedContainer = nn.Container()

  for t = 1, #unrolled_model do
    sharedContainer:add(unrolled_model[t])
  end

  return sharedContainer
end

function model_utils.convert_model(options, model)
  local output_model
  if options.backend == 'cpu' then
    output_model = model
  elseif options.backend == 'cuda' or options.backend == 'cudnn' then
    output_model = model:cuda()
    if options.backend == 'cudnn' then
      local cudnn = require('cudnn')
      cudnn.convert(output_model, cudnn)
    end
  else
    error('Invalid Backend!')
  end

  return output_model
end

function model_utils.addLearnedBias(options, model, mode)
  local input_size = options.input_size
  local img_size = options.img_size

  local updatedModel = nn.Sequential()

  local learnedParams = nn.ParallelTable()

  -- Forward the first input
  -- If we are in training mode then it's the training images
  -- If we are in evaluation mode, then the first input corresponds
  -- to the latent variable.
  learnedParams:add(nn.Identity())

  -- Create the learnable canvas
  local learnedCanvas = nn.Sequential()
  -- Reshape the input into a continuous vector
  learnedCanvas:add(nn.View(-1, input_size))
  -- Add the learnable bias
  learnedCanvas:add(nn.Add(input_size))
  -- Reshape the canvas so as to match the image size
  learnedCanvas:add(nn.View(-1, table.unpack(img_size:totable())))

  learnedParams:add(learnedCanvas)

  -- Add the encoder only in training mode
  if mode == 'training' then
    -- Create the learnable initial hidden state for the encoder
    local learnedHiddenEncoder = nn.Sequential()
    learnedHiddenEncoder:add(nn.Add(options.hidden_size))

    learnedParams:add(learnedHiddenEncoder)
  end

  if mode == 'training' then
    -- Just forward the cell state for the encoder
    learnedParams:add(nn.Identity())
  end

  -- Create the learnable initial hidden state for the decoder
  local learnedHiddenDecoder = nn.Sequential()
  learnedHiddenDecoder:add(nn.Add(options.hidden_size))

  learnedParams:add(learnedHiddenDecoder)

  -- Forward the cell state for the decoder
  learnedParams:add(nn.Identity())

  updatedModel:add(learnedParams)
  updatedModel:add(model)

  return updatedModel, learnedParams
end

return model_utils
