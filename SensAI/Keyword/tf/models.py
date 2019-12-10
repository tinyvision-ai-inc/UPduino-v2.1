# Copyright 2017 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
"""Model definitions for simple speech recognition.

"""
from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import math

import tensorflow as tf
from tensorflow.python.training import moving_averages


def prepare_model_settings(label_count, sample_rate, clip_duration_ms,
                           window_size_ms, window_stride_ms,
                           dct_coefficient_count):
  """Calculates common settings needed for all models.

  Args:
    label_count: How many classes are to be recognized.
    sample_rate: Number of audio samples per second.
    clip_duration_ms: Length of each audio clip to be analyzed.
    window_size_ms: Duration of frequency analysis window.
    window_stride_ms: How far to move in time between frequency windows.
    dct_coefficient_count: Number of frequency bins to use for analysis.

  Returns:
    Dictionary containing common settings.
  """
  desired_samples = int(sample_rate * clip_duration_ms / 1000)
  window_size_samples = int(sample_rate * window_size_ms / 1000)
  window_stride_samples = int(sample_rate * window_stride_ms / 1000)
  length_minus_window = (desired_samples - window_size_samples)
  if length_minus_window < 0:
    spectrogram_length = 0
  else:
    spectrogram_length = 1 + int(length_minus_window / window_stride_samples)
  fingerprint_size = dct_coefficient_count * spectrogram_length
  return {
      'desired_samples': desired_samples,
      'window_size_samples': window_size_samples,
      'window_stride_samples': window_stride_samples,
      'spectrogram_length': spectrogram_length,
      'dct_coefficient_count': dct_coefficient_count,
      'fingerprint_size': fingerprint_size,
      'label_count': label_count,
      'sample_rate': sample_rate,
  }


def create_model(audio_input, model_settings, model_architecture,
                 is_training, runtime_settings=None,
                 norm_binw=False,
                 downsample=1,
                 lock_prefilter=False, add_prefilter_bias=True, use_down_avgfilt=False):
  """Builds a model of the requested architecture compatible with the settings.

  There are many possible ways of deriving predictions from a spectrogram
  input, so this function provides an abstract interface for creating different
  kinds of models in a black-box way. You need to pass in a TensorFlow node as
  the 'fingerprint' input, and this should output a batch of 1D features that
  describe the audio. Typically this will be derived from a spectrogram that's
  been run through an MFCC, but in theory it can be any feature vector of the
  size specified in model_settings['fingerprint_size'].

  The function will build the graph it needs in the current TensorFlow graph,
  and return the tensorflow output that will contain the 'logits' input to the
  softmax prediction process. If training flag is on, it will also return a
  placeholder node that can be used to control the dropout amount.

  See the implementations below for the possible model architectures that can be
  requested.

  Args:
    fingerprint_input: TensorFlow node that will output audio feature vectors.
    model_settings: Dictionary of information about the model.
    model_architecture: String specifying which kind of model to create.
    is_training: Whether the model is going to be used for training.
    runtime_settings: Dictionary of information about the runtime.

  Returns:
    TensorFlow node outputting logits results, and optionally a dropout
    placeholder.

  Raises:
    Exception: If the architecture type isn't recognized.
  """
  fingerprint_input = create_spectrogram(audio_input, model_settings, is_training,
                                         downsample=downsample,
                                         add_bias=add_prefilter_bias,
                                         use_avgfilt=use_down_avgfilt)

  tf.summary.histogram('fingerprint_input', fingerprint_input) 

  if lock_prefilter:
    fingerprint_input = tf.stop_gradient(fingerprint_input)

  if model_architecture == 'single_fc':
    return create_single_fc_model(fingerprint_input, model_settings,
                                  is_training)
  elif model_architecture == 'conv':
    return create_conv_model(fingerprint_input, model_settings, is_training)
  elif model_architecture == 'low_latency_conv':
    return create_low_latency_conv_model(fingerprint_input, model_settings,
                                         is_training)
  elif model_architecture == 'low_latency_svdf':
    return create_low_latency_svdf_model(fingerprint_input, model_settings,
                                         is_training, runtime_settings)
  elif model_architecture == 'medium_conv':
    return create_medium_conv_model(fingerprint_input, model_settings,
                                    is_training)
  # 32x32 input
  elif model_architecture == 'small_conv':
    return create_small_conv_model(fingerprint_input, model_settings,
                                   is_training)
  # + 3x3 kernel
  elif model_architecture == 'tiny_conv':
    return create_tiny_conv_model(fingerprint_input, model_settings,
                                  is_training)
  #--------------- Prefilter
  elif model_architecture == 'ex_conv':
    return create_ex_conv_model(fingerprint_input, model_settings, is_training)
  # 4 stage vgg-net
  elif model_architecture == 'tinyex_conv':
    return create_tinyex_conv_model(fingerprint_input, model_settings,
                                    is_training)
  elif model_architecture == 'binary_conv':
    return create_binary_conv_model(fingerprint_input, model_settings,
                                    is_training)
  # 5 stage + straight
  elif model_architecture == 'tinyex2_conv':
    return create_tinyex2_conv_model(fingerprint_input, model_settings,
                                     is_training)
  elif model_architecture == 'quatery2_conv':
    return create_quatery2_conv_model(fingerprint_input, model_settings,
                                    is_training)
  elif model_architecture == 'binary2_conv':
    return create_binary2_conv_model(fingerprint_input, model_settings,
                                    is_training)
  # 4 stage + straight
  elif model_architecture == 'tinyex3_conv':
    return create_tinyex3_conv_model(fingerprint_input, model_settings,
                                    is_training, filt_k=4)
  elif model_architecture == 'binary_weights3_conv':
    return create_binary_weights3_conv_model(fingerprint_input, model_settings,
                                    is_training)
  elif model_architecture == 'binary3_conv':
    return create_binary3_conv_model(fingerprint_input, model_settings,
                                    is_training,
                                    normw=norm_binw, stochastic=False)
  elif model_architecture == 'binary3a_conv':
    return create_binary3_conv_model(fingerprint_input, model_settings,
                                    is_training,
                                    no_pool3=True,
                                    normw=norm_binw, stochastic=False)
  elif model_architecture == 'tinyex4_conv':
    return create_tinyex3_conv_model(fingerprint_input, model_settings,
                                    is_training, filt_k=1)
  elif model_architecture == 'tinyvgg_conv':
    return create_tinyvgg_conv_model(fingerprint_input, model_settings,
                                    is_training, filt_k=2)
  else:
    raise Exception('model_architecture argument "' + model_architecture +
                    '" not recognized, should be one of "single_fc", "conv",' +
                    ' "low_latency_conv, or "low_latency_svdf"')


def load_variables_from_checkpoint(sess, start_checkpoint):
  """Utility function to centralize checkpoint restoration.

  Args:
    sess: TensorFlow session.
    start_checkpoint: Path to saved checkpoint on disk.
  """
  saver = tf.train.Saver(tf.global_variables())
  saver.restore(sess, start_checkpoint)


def init_variables_from_checkpoint(sess, init_checkpoint, scope=None):
  """Utility function to centralize checkpoint restoration.

  Args:
    sess: TensorFlow session.
    start_checkpoint: Path to saved checkpoint on disk.
  """
  if sess is None:
    assert scope
    tf.train.init_from_checkpoint(init_checkpoint, {scope:scope})
  else:
    if scope:
      global spectrogram_filter
      saver = tf.train.Saver(spectrogram_filter)
      saver.restore(sess, init_checkpoint)
    else:
      saver = tf.train.Saver(tf.global_variables())
      saver.restore(sess, init_checkpoint)


def create_single_fc_model(fingerprint_input, model_settings, is_training):
  """Builds a model with a single hidden fully-connected layer.

  This is a very simple model with just one matmul and bias layer. As you'd
  expect, it doesn't produce very accurate results, but it is very fast and
  simple, so it's useful for sanity testing.

  Here's the layout of the graph:

  (fingerprint_input)
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v

  Args:
    fingerprint_input: TensorFlow node that will output audio feature vectors.
    model_settings: Dictionary of information about the model.
    is_training: Whether the model is going to be used for training.

  Returns:
    TensorFlow node outputting logits results, and optionally a dropout
    placeholder.
  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  fingerprint_size = model_settings['fingerprint_size']
  label_count = model_settings['label_count']
  weights = tf.Variable(
      tf.truncated_normal([fingerprint_size, label_count], stddev=0.001))
  bias = tf.Variable(tf.zeros([label_count]))
  logits = tf.matmul(fingerprint_input, weights) + bias
  if is_training:
    return logits, dropout_prob
  else:
    return logits


def create_conv_model(fingerprint_input, model_settings, is_training):
  """Builds a standard convolutional model.

  This is roughly the network labeled as 'cnn-trad-fpool3' in the
  'Convolutional Neural Networks for Small-footprint Keyword Spotting' paper:
  http://www.isca-speech.org/archive/interspeech_2015/papers/i15_1478.pdf

  Here's the layout of the graph:

  (fingerprint_input)
          v
      [Conv2D]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
        [Relu]
          v
      [MaxPool]
          v
      [Conv2D]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
        [Relu]
          v
      [MaxPool]
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v

  This produces fairly good quality results, but can involve a large number of
  weight parameters and computations. For a cheaper alternative from the same
  paper with slightly less accuracy, see 'low_latency_conv' below.

  During training, dropout nodes are introduced after each relu, controlled by a
  placeholder.

  Args:
    fingerprint_input: TensorFlow node that will output audio feature vectors.
    model_settings: Dictionary of information about the model.
    is_training: Whether the model is going to be used for training.

  Returns:
    TensorFlow node outputting logits results, and optionally a dropout
    placeholder.
  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, input_time_size, input_frequency_size, 1])
  first_filter_width = 8
  first_filter_height = 20
  first_filter_count = 64
  first_weights = tf.Variable(
      tf.truncated_normal(
          [first_filter_height, first_filter_width, 1, first_filter_count],
          stddev=0.01))
  first_bias = tf.Variable(tf.zeros([first_filter_count]))
  first_conv = tf.nn.conv2d(fingerprint_4d, first_weights, [1, 1, 1, 1],
                            'SAME') + first_bias
  first_relu = tf.nn.relu(first_conv)
  if is_training:
    first_dropout = tf.nn.dropout(first_relu, dropout_prob)
  else:
    first_dropout = first_relu
  max_pool = tf.nn.max_pool(first_dropout, [1, 2, 2, 1], [1, 2, 2, 1], 'SAME')
  second_filter_width = 4
  second_filter_height = 10
  second_filter_count = 64
  second_weights = tf.Variable(
      tf.truncated_normal(
          [
              second_filter_height, second_filter_width, first_filter_count,
              second_filter_count
          ],
          stddev=0.01))
  second_bias = tf.Variable(tf.zeros([second_filter_count]))
  second_conv = tf.nn.conv2d(max_pool, second_weights, [1, 1, 1, 1],
                             'SAME') + second_bias
  second_relu = tf.nn.relu(second_conv)
  if is_training:
    second_dropout = tf.nn.dropout(second_relu, dropout_prob)
  else:
    second_dropout = second_relu
  second_conv_shape = second_dropout.get_shape()
  second_conv_output_width = second_conv_shape[2]
  second_conv_output_height = second_conv_shape[1]
  second_conv_element_count = int(
      second_conv_output_width * second_conv_output_height *
      second_filter_count)
  flattened_second_conv = tf.reshape(second_dropout,
                                     [-1, second_conv_element_count])
  label_count = model_settings['label_count']
  final_fc_weights = tf.Variable(
      tf.truncated_normal(
          [second_conv_element_count, label_count], stddev=0.01))
  final_fc_bias = tf.Variable(tf.zeros([label_count]))
  final_fc = tf.matmul(flattened_second_conv, final_fc_weights) + final_fc_bias
  if is_training:
    return final_fc, dropout_prob
  else:
    return final_fc


def create_low_latency_conv_model(fingerprint_input, model_settings,
                                  is_training):
  """Builds a convolutional model with low compute requirements.

  This is roughly the network labeled as 'cnn-one-fstride4' in the
  'Convolutional Neural Networks for Small-footprint Keyword Spotting' paper:
  http://www.isca-speech.org/archive/interspeech_2015/papers/i15_1478.pdf

  Here's the layout of the graph:

  (fingerprint_input)
          v
      [Conv2D]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
        [Relu]
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v

  This produces slightly lower quality results than the 'conv' model, but needs
  fewer weight parameters and computations.

  During training, dropout nodes are introduced after the relu, controlled by a
  placeholder.

  Args:
    fingerprint_input: TensorFlow node that will output audio feature vectors.
    model_settings: Dictionary of information about the model.
    is_training: Whether the model is going to be used for training.

  Returns:
    TensorFlow node outputting logits results, and optionally a dropout
    placeholder.
  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, input_time_size, input_frequency_size, 1])
  first_filter_width = 8
  first_filter_height = input_time_size
  first_filter_count = 186
  first_filter_stride_x = 1
  first_filter_stride_y = 1
  first_weights = tf.Variable(
      tf.truncated_normal(
          [first_filter_height, first_filter_width, 1, first_filter_count],
          stddev=0.01))
  first_bias = tf.Variable(tf.zeros([first_filter_count]))
  first_conv = tf.nn.conv2d(fingerprint_4d, first_weights, [
      1, first_filter_stride_y, first_filter_stride_x, 1
  ], 'VALID') + first_bias
  first_relu = tf.nn.relu(first_conv)
  if is_training:
    first_dropout = tf.nn.dropout(first_relu, dropout_prob)
  else:
    first_dropout = first_relu
  first_conv_output_width = math.floor(
      (input_frequency_size - first_filter_width + first_filter_stride_x) /
      first_filter_stride_x)
  first_conv_output_height = math.floor(
      (input_time_size - first_filter_height + first_filter_stride_y) /
      first_filter_stride_y)
  first_conv_element_count = int(
      first_conv_output_width * first_conv_output_height * first_filter_count)
  flattened_first_conv = tf.reshape(first_dropout,
                                    [-1, first_conv_element_count])
  first_fc_output_channels = 128
  first_fc_weights = tf.Variable(
      tf.truncated_normal(
          [first_conv_element_count, first_fc_output_channels], stddev=0.01))
  first_fc_bias = tf.Variable(tf.zeros([first_fc_output_channels]))
  first_fc = tf.matmul(flattened_first_conv, first_fc_weights) + first_fc_bias
  if is_training:
    second_fc_input = tf.nn.dropout(first_fc, dropout_prob)
  else:
    second_fc_input = first_fc
  second_fc_output_channels = 128
  second_fc_weights = tf.Variable(
      tf.truncated_normal(
          [first_fc_output_channels, second_fc_output_channels], stddev=0.01))
  second_fc_bias = tf.Variable(tf.zeros([second_fc_output_channels]))
  second_fc = tf.matmul(second_fc_input, second_fc_weights) + second_fc_bias
  if is_training:
    final_fc_input = tf.nn.dropout(second_fc, dropout_prob)
  else:
    final_fc_input = second_fc
  label_count = model_settings['label_count']
  final_fc_weights = tf.Variable(
      tf.truncated_normal(
          [second_fc_output_channels, label_count], stddev=0.01))
  final_fc_bias = tf.Variable(tf.zeros([label_count]))
  final_fc = tf.matmul(final_fc_input, final_fc_weights) + final_fc_bias
  if is_training:
    return final_fc, dropout_prob
  else:
    return final_fc


def create_low_latency_svdf_model(fingerprint_input, model_settings,
                                  is_training, runtime_settings):
  """Builds an SVDF model with low compute requirements.

  This is based in the topology presented in the 'Compressing Deep Neural
  Networks using a Rank-Constrained Topology' paper:
  https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/43813.pdf

  Here's the layout of the graph:

  (fingerprint_input)
          v
        [SVDF]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
        [Relu]
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v
      [MatMul]<-(weights)
          v
      [BiasAdd]<-(bias)
          v

  This model produces lower recognition accuracy than the 'conv' model above,
  but requires fewer weight parameters and, significantly fewer computations.

  During training, dropout nodes are introduced after the relu, controlled by a
  placeholder.

  Args:
    fingerprint_input: TensorFlow node that will output audio feature vectors.
    The node is expected to produce a 2D Tensor of shape:
      [batch, model_settings['dct_coefficient_count'] *
              model_settings['spectrogram_length']]
    with the features corresponding to the same time slot arranged contiguously,
    and the oldest slot at index [:, 0], and newest at [:, -1].
    model_settings: Dictionary of information about the model.
    is_training: Whether the model is going to be used for training.
    runtime_settings: Dictionary of information about the runtime.

  Returns:
    TensorFlow node outputting logits results, and optionally a dropout
    placeholder.

  Raises:
      ValueError: If the inputs tensor is incorrectly shaped.
  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')

  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']

  # Validation.
  input_shape = fingerprint_input.get_shape()
  if len(input_shape) != 2:
    raise ValueError('Inputs to `SVDF` should have rank == 2.')
  if input_shape[-1].value is None:
    raise ValueError('The last dimension of the inputs to `SVDF` '
                     'should be defined. Found `None`.')
  if input_shape[-1].value % input_frequency_size != 0:
    raise ValueError('Inputs feature dimension %d must be a multiple of '
                     'frame size %d', fingerprint_input.shape[-1].value,
                     input_frequency_size)

  # Set number of units (i.e. nodes) and rank.
  rank = 2
  num_units = 1280
  # Number of filters: pairs of feature and time filters.
  num_filters = rank * num_units
  # Create the runtime memory: [num_filters, batch, input_time_size]
  batch = 1
  memory = tf.Variable(tf.zeros([num_filters, batch, input_time_size]),
                       trainable=False, name='runtime-memory')
  # Determine the number of new frames in the input, such that we only operate
  # on those. For training we do not use the memory, and thus use all frames
  # provided in the input.
  # new_fingerprint_input: [batch, num_new_frames*input_frequency_size]
  if is_training:
    num_new_frames = input_time_size
  else:
    window_stride_ms = int(model_settings['window_stride_samples'] * 1000 /
                           model_settings['sample_rate'])
    num_new_frames = tf.cond(
        tf.equal(tf.count_nonzero(memory), 0),
        lambda: input_time_size,
        lambda: int(runtime_settings['clip_stride_ms'] / window_stride_ms))
  new_fingerprint_input = fingerprint_input[
      :, -num_new_frames*input_frequency_size:]
  # Expand to add input channels dimension.
  new_fingerprint_input = tf.expand_dims(new_fingerprint_input, 2)

  # Create the frequency filters.
  weights_frequency = tf.Variable(
      tf.truncated_normal([input_frequency_size, num_filters], stddev=0.01))
  # Expand to add input channels dimensions.
  # weights_frequency: [input_frequency_size, 1, num_filters]
  weights_frequency = tf.expand_dims(weights_frequency, 1)
  # Convolve the 1D feature filters sliding over the time dimension.
  # activations_time: [batch, num_new_frames, num_filters]
  activations_time = tf.nn.conv1d(
      new_fingerprint_input, weights_frequency, input_frequency_size, 'VALID')
  # Rearrange such that we can perform the batched matmul.
  # activations_time: [num_filters, batch, num_new_frames]
  activations_time = tf.transpose(activations_time, perm=[2, 0, 1])

  # Runtime memory optimization.
  if not is_training:
    # We need to drop the activations corresponding to the oldest frames, and
    # then add those corresponding to the new frames.
    new_memory = memory[:, :, num_new_frames:]
    new_memory = tf.concat([new_memory, activations_time], 2)
    tf.assign(memory, new_memory)
    activations_time = new_memory

  # Create the time filters.
  weights_time = tf.Variable(
      tf.truncated_normal([num_filters, input_time_size], stddev=0.01))
  # Apply the time filter on the outputs of the feature filters.
  # weights_time: [num_filters, input_time_size, 1]
  # outputs: [num_filters, batch, 1]
  weights_time = tf.expand_dims(weights_time, 2)
  outputs = tf.matmul(activations_time, weights_time)
  # Split num_units and rank into separate dimensions (the remaining
  # dimension is the input_shape[0] -i.e. batch size). This also squeezes
  # the last dimension, since it's not used.
  # [num_filters, batch, 1] => [num_units, rank, batch]
  outputs = tf.reshape(outputs, [num_units, rank, -1])
  # Sum the rank outputs per unit => [num_units, batch].
  units_output = tf.reduce_sum(outputs, axis=1)
  # Transpose to shape [batch, num_units]
  units_output = tf.transpose(units_output)

  # Appy bias.
  bias = tf.Variable(tf.zeros([num_units]))
  first_bias = tf.nn.bias_add(units_output, bias)

  # Relu.
  first_relu = tf.nn.relu(first_bias)

  if is_training:
    first_dropout = tf.nn.dropout(first_relu, dropout_prob)
  else:
    first_dropout = first_relu

  first_fc_output_channels = 256
  first_fc_weights = tf.Variable(
      tf.truncated_normal([num_units, first_fc_output_channels], stddev=0.01))
  first_fc_bias = tf.Variable(tf.zeros([first_fc_output_channels]))
  first_fc = tf.matmul(first_dropout, first_fc_weights) + first_fc_bias
  if is_training:
    second_fc_input = tf.nn.dropout(first_fc, dropout_prob)
  else:
    second_fc_input = first_fc
  second_fc_output_channels = 256
  second_fc_weights = tf.Variable(
      tf.truncated_normal(
          [first_fc_output_channels, second_fc_output_channels], stddev=0.01))
  second_fc_bias = tf.Variable(tf.zeros([second_fc_output_channels]))
  second_fc = tf.matmul(second_fc_input, second_fc_weights) + second_fc_bias
  if is_training:
    final_fc_input = tf.nn.dropout(second_fc, dropout_prob)
  else:
    final_fc_input = second_fc
  label_count = model_settings['label_count']
  final_fc_weights = tf.Variable(
      tf.truncated_normal(
          [second_fc_output_channels, label_count], stddev=0.01))
  final_fc_bias = tf.Variable(tf.zeros([label_count]))
  final_fc = tf.matmul(final_fc_input, final_fc_weights) + final_fc_bias
  if is_training:
    return final_fc, dropout_prob
  else:
    return final_fc


#-----------------------------------------------------
# from r2rt.com
def batch_norm_wrapper(inputs, is_training, scale=True, decay=0.999, epsilon=1e-5):
    dim = inputs.get_shape()
    num_channel = dim[-1]
    scale_v = tf.Variable(tf.ones([num_channel]), name='batchnorm/alpha') if scale else None
    beta = tf.Variable(tf.zeros([num_channel]), name='batchnorm/beta')
    pop_mean = tf.Variable(tf.zeros([num_channel]), trainable=False, name='batchnorm/mean')
    pop_var = tf.Variable(tf.ones([num_channel]), trainable=False, name='batchnorm/var')

    if is_training:
        batch_mean, batch_var = tf.nn.moments(inputs, list(range(len(dim)-1)), name='moments')
        train_mean = tf.assign(pop_mean,
                               pop_mean * decay + batch_mean * (1 - decay))
        train_var = tf.assign(pop_var,
                              pop_var * decay + batch_var * (1 - decay))
        with tf.control_dependencies([train_mean, train_var]):
            return tf.nn.batch_normalization(inputs,
                batch_mean, batch_var, beta, scale_v, epsilon)
    else:
        return tf.nn.batch_normalization(inputs,
            pop_mean, pop_var, beta, scale_v, epsilon)

def _activation_summary(x):
  tensor_name = x.op.name.rsplit('/', 1)[-1]
  tf.summary.histogram(tensor_name + '/activations', x)
  tf.summary.scalar(tensor_name + '/sparsity',
                                       tf.nn.zero_fraction(x))


import librosa
import numpy as np

spectrogram_filter = None

def create_spectrogram(audio_input, model_settings, is_training, downsample=1, add_bias=False, use_avgfilt=False):
  sample_size   = model_settings['desired_samples'] // downsample
  filter_width  = model_settings['window_size_samples'] // downsample
  filter_count  = model_settings['dct_coefficient_count']
  filter_stride = model_settings['window_stride_samples'] // downsample
  if downsample == 1:
    #audio_input_3d = tf.reshape(audio_input, [-1, sample_size, 1])
    audio_input_3d = tf.expand_dims(audio_input, -1)
  elif use_avgfilt and downsample == 4:
    sel_filter = tf.convert_to_tensor([[[0.5]], [[0]], [[0.5]], [[0]]], dtype=tf.float32)
    #audio_input_3d = tf.nn.conv1d(audio_input, sel_filter, 4, padding='VALID')
    audio_input_3d = tf.nn.conv1d(tf.expand_dims(audio_input, -1), sel_filter, 4, padding='VALID')
    print(audio_input_3d.get_shape().as_list())
  else:
    print("downsampling to {}".format(downsample))
    #print(audio_input.get_shape().as_list())
    #print(audio_input[:,::downsample].get_shape().as_list())
    audio_input_3d = tf.expand_dims(audio_input[...,::downsample], -1)
    #audio_input_3d = tf.expand_dims(audio_input[...,downsample//2::downsample], -1)    # center pick
  #
  #_dct_filters = librosa.filters.dct(filter_count, filter_width)
  #print(_dct_filters.shape)
  #_dct_filters = np.expand_dims(np.transpose(_dct_filters,(1,0)),1)
  if False:
    dct_filters = tf.convert_to_tensor(_dct_filters, dtype=tf.float32)
    out = tf.nn.conv1d(audio_input_3d, dct_filters, filter_stride, padding='SAME')
    return out
  with tf.variable_scope('freqconv') as scope:
    weights = tf.get_variable('weights', shape=[filter_width, 1, filter_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    #weights = tf.get_variable('weights', initializer=tf.constant_initializer(_dct_filters))
    tf.summary.histogram('weights', weights)
    conv = tf.nn.conv1d(audio_input_3d, weights, filter_stride, padding='VALID')

    global spectrogram_filter
    if False:   # BatchNorm
      norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                                is_training=is_training)
      out = tf.nn.relu(norm, name='relu')
    elif add_bias: # Bias
      bias = tf.get_variable('biases', shape=[filter_count],
                    initializer=tf.constant_initializer(0))
      tf.summary.histogram('biases', bias)
      #out = tf.nn.relu(tf.nn.bias_add(conv, bias), name='relu')
      out = binary_wrapper(tf.nn.bias_add(conv, bias), a_bin=8, min_rng=0.0, max_rng=2.0) 
      spectrogram_filter = [weights, bias]
    else:
      #out = tf.nn.relu(conv, name='relu')
      out = binary_wrapper(conv, a_bin=8, min_rng=0.0, max_rng=2.0) 
      spectrogram_filter = [weights]
    _activation_summary(out)
    print(weights.get_shape().as_list())
  print(audio_input_3d.get_shape().as_list())
  print(out.get_shape().as_list())
  return out


# 8x2 kernel
def create_medium_conv_model(fingerprint_input, model_settings,
                            is_training):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, input_time_size, input_frequency_size, 1])
  # conv1 (kernel: 16x4)
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[20, 8, 1, 16],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[10, 4, 16, 32],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # pool2
  pool2 = tf.nn.max_pool(norm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # fc3
  if is_training:
    fc_input = tf.nn.dropout(pool2, dropout_prob)
  else:
    fc_input = pool2

  label_count = model_settings['label_count']
  with tf.variable_scope('fc3') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.0))
    fc = tf.matmul(reshape, weights) # no bias
    fc3 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc3)

  if is_training:
    return fc3, dropout_prob
  else:
    return fc3

#-----------------------------------------------------
# 8x2 kernel
def create_small_conv_model(fingerprint_input, model_settings,
                            is_training):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, input_time_size, input_frequency_size, 1])
  # conv1 (kernel: 16x4)
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[16, 4, 1, 16],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[8, 2, 16, 32],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # pool2
  pool2 = tf.nn.max_pool(norm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # fc3
  if is_training:
    fc_input = tf.nn.dropout(pool2, dropout_prob)
  else:
    fc_input = pool2

  label_count = model_settings['label_count']
  with tf.variable_scope('fc3') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.0))
    fc = tf.matmul(reshape, weights) # no bias
    fc3 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc3)

  if is_training:
    return fc3, dropout_prob
  else:
    return fc3

#-----------------------------------------------------
from binary_ops import binarize, binary_sigmoid, binary_tanh, binary_relu, quatery_relu

def binconv2d(x, W, layer_name, normw=False, depthwise=False, stochastic=False):
  with tf.name_scope(layer_name):
    with tf.name_scope('weights'):
      tf.summary.histogram('histogram', W)
    with tf.name_scope('BinWeights'):
      Wb = binarize(W, normalize=normw, stochastic=stochastic)
      tf.summary.histogram('BinWeights', Wb)
    if depthwise:
      conv_out = tf.nn.depthwise_conv2d(x, Wb, strides=[1, 1, 1, 1], padding='SAME')
    else:
      conv_out = tf.nn.conv2d(x, Wb, strides=[1, 1, 1, 1], padding='SAME')
    tf.summary.histogram('Convout', conv_out)
    output = conv_out   # no bias
  return output

def binfullcon(x, W, layer_name, normw=False, stochastic=False):
  with tf.name_scope(layer_name):
    with tf.name_scope('weights'):
      tf.summary.histogram('histogram', W)
    with tf.name_scope('BinWeights'):
      Wb = binarize(W, normalize=normw, stochastic=stochastic)
      tf.summary.histogram('BinWeights', Wb)
    fc_out = tf.matmul(x, Wb) # no bias
    tf.summary.histogram('Fcout', fc_out)
    #output = fc_out+b
    output = fc_out   # no bias
  return output


#-----------------------------------------------------
# 3x3 kernel
def create_tiny_conv_model(fingerprint_input, model_settings,
                             is_training,
                             filt_k=1):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, input_time_size, input_frequency_size, 1])
  # conv1
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 1, 16*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 16*filt_k, 32*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # pool2
  pool2 = tf.nn.max_pool(norm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 32*filt_k, 64*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool2, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm3 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm3)

  # pool3
  pool3 = tf.nn.max_pool(norm3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc4
  if is_training:
    fc_input = tf.nn.dropout(pool3, dropout_prob)
  else:
    fc_input = pool3

  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = tf.matmul(reshape, weights) # no bias
    fc4 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc4)

  if is_training:
    return fc4, dropout_prob
  else:
    return fc4


#########################################################################
# 4 stage
def create_tinyex_conv_model(fingerprint_input, model_settings,
                             is_training,
                             filt_k=1, depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  if True:
    # HCW  (whole picture in one plane)
    _fingerprint_4d = tf.reshape(fingerprint_input,
                                [-1, 32, input_depth, input_frequency_size])
    fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  else:
    # CHW
    _fingerprint_4d = tf.reshape(fingerprint_input,
                                [-1, input_depth, 32, input_frequency_size])
    fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 2, 3, 1])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    if depthwise_conv1:
      channel_multiplier = (32//input_depth)*filt_k
      kernel = tf.get_variable('depth_filter', shape=[3, 3, input_depth, channel_multiplier],
                      initializer=tf.contrib.layers.xavier_initializer())
      conv = tf.nn.depthwise_conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    else:
      kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 32*filt_k],
                      initializer=tf.contrib.layers.xavier_initializer())
      conv = tf.nn.conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, pool1.get_shape().as_list()[-1], 32*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # pool2
  pool2 = tf.nn.max_pool(norm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 32*filt_k, 64*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool2, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm3 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm3)

  # pool3
  pool3 = tf.nn.max_pool(norm3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc4
  if is_training:
    fc_input = tf.nn.dropout(pool3, dropout_prob)
  else:
    fc_input = pool3

  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = tf.matmul(reshape, weights) # no bias
    fc4 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc4)

  if is_training:
    return fc4, dropout_prob
  else:
    return fc4


def create_binary_conv_model(fingerprint_input, model_settings,
                             is_training,
                             depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv-> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    if depthwise_conv1:
      channel_multiplier = (32//input_depth)
      kernel = tf.get_variable('depth_filter', shape=[3, 3, input_depth, channel_multiplier],
                      initializer=tf.contrib.layers.xavier_initializer())
    else:
      kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 32],
                      initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv1', depthwise=depthwise_conv1)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin1 = binary_tanh(norm)   # [-1,1]
    #bin1 = binary_sigmoid(norm) # [0,1]
    bin1 = binary_relu(norm) # [0,1]
    _activation_summary(bin1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(bin1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, pool1.get_shape().as_list()[-1], 32],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool1, kernel, 'conv2')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin2 = binary_tanh(norm)
    #bin2 = binary_sigmoid(norm)
    bin2 = binary_relu(norm)
    _activation_summary(bin2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(bin2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 32, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool2, kernel, 'conv3')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin3 = binary_tanh(norm)
    #bin3 = binary_sigmoid(norm)
    bin3 = binary_relu(norm)
    _activation_summary(bin3)

  # pool3 (4x4)
  pool3 = tf.nn.max_pool(bin3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc4
  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = pool3.get_shape()
    reshape = tf.reshape(pool3, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = binfullcon(reshape, weights, 'fc4')
    fc4 = tf.nn.bias_add(fc, biases)
    _activation_summary(fc4)

  if is_training:
    return fc4, dropout_prob
  else:
    return fc4

#########################################################################
# 5 stage
def create_tinyex2_conv_model(fingerprint_input, model_settings,
                             is_training,
                             depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> conv -> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    if depthwise_conv1:
      channel_multiplier = (64//input_depth)
      kernel = tf.get_variable('depth_filter', shape=[3, 3, input_depth, channel_multiplier],
                      initializer=tf.contrib.layers.xavier_initializer())
    else:
      kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 64],
                      initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv1', depthwise=depthwise_conv1)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, pool1.get_shape().as_list()[-1], 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(norm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool2, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm3 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm3)

  # pool3 (4x4)
  #pool3 = tf.nn.max_pool(norm3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
  #                       padding='SAME', name='pool3')
  pool3 = norm3

  # conv4
  with tf.variable_scope('conv4') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool3, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm4 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm4)

  # pool4 (2x2)
  pool4 = tf.nn.max_pool(norm4, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool4')

  # fc5
  if is_training:
    fc_input = tf.nn.dropout(pool4, dropout_prob)
  else:
    fc_input = pool4

  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = tf.matmul(reshape, weights) # no bias
    fc5 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc5)

  if is_training:
    return fc5, dropout_prob
  else:
    return fc5


def create_binary_weights2_conv_model(fingerprint_input, model_settings,
                             is_training,
                             depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> conv-> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    if depthwise_conv1:
      channel_multiplier = (32//input_depth)
      kernel = tf.get_variable('depth_filter', shape=[3, 3, input_depth, channel_multiplier],
                      initializer=tf.contrib.layers.xavier_initializer())
    else:
      kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 32],
                      initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv1', depthwise=depthwise_conv1)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv1 = tf.nn.relu(norm)
    _activation_summary(conv1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(conv1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, pool1.get_shape().as_list()[-1], 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool1, kernel, 'conv')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv2 = tf.nn.relu(norm)
    _activation_summary(conv2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(conv2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool2, kernel, 'conv')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv3 = tf.nn.relu(norm)
    _activation_summary(conv3)

  # pool3 (4x4)
  #pool3 = tf.nn.max_pool(conv3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
  #                       padding='SAME', name='pool3')
  pool3 = conv3

  # conv4
  with tf.variable_scope('conv4') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool3, kernel, 'conv4')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv4 = tf.nn.relu(norm)
    _activation_summary(conv4)

  # pool4 (2x2)
  pool4 = tf.nn.max_pool(conv4, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool4')

  # fc5
  if is_training:
    fc_input = tf.nn.dropout(pool4, dropout_prob)
  else:
    fc_input = pool4

  label_count = model_settings['label_count']
  with tf.variable_scope('fc5') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = binfullcon(reshape, weights, 'fc5')
    fc5 = tf.nn.bias_add(fc, biases)
    _activation_summary(fc5)

  if is_training:
    return fc5, dropout_prob
  else:
    return fc5


def create_quatery2_conv_model(fingerprint_input, model_settings,
                             is_training,
                             depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> conv-> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    if depthwise_conv1:
      channel_multiplier = (32//input_depth)
      kernel = tf.get_variable('depth_filter', shape=[3, 3, input_depth, channel_multiplier],
                      initializer=tf.contrib.layers.xavier_initializer())
    else:
      kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 32],
                      initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv1', depthwise=depthwise_conv1)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    qnorm1 = quatery_relu(norm) # [0,1,2,4]
    _activation_summary(qnorm1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(qnorm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, pool1.get_shape().as_list()[-1], 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool1, kernel, 'conv')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    qnorm2 = quatery_relu(norm)
    _activation_summary(qnorm2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(qnorm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool2, kernel, 'conv')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    qnorm3 = quatery_relu(norm)
    _activation_summary(qnorm3)

  # pool3 (4x4)
  #pool3 = tf.nn.max_pool(qnorm3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
  #                       padding='SAME', name='pool3')
  pool3 = qnorm3

  # conv4
  with tf.variable_scope('conv4') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool3, kernel, 'conv4')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    qnorm4 = quatery_relu(norm)
    _activation_summary(qnorm4)

  # pool4 (2x2)
  pool4 = tf.nn.max_pool(qnorm4, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc5
  label_count = model_settings['label_count']
  with tf.variable_scope('fc5') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = pool4.get_shape()
    reshape = tf.reshape(pool4, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = binfullcon(reshape, weights, 'fc5')
    fc5 = tf.nn.bias_add(fc, biases)
    _activation_summary(fc5)

  if is_training:
    return fc5, dropout_prob
  else:
    return fc5


def create_binary2_conv_model(fingerprint_input, model_settings,
                             is_training,
                             depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> conv-> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    if depthwise_conv1:
      channel_multiplier = (32//input_depth)
      kernel = tf.get_variable('depth_filter', shape=[3, 3, input_depth, channel_multiplier],
                      initializer=tf.contrib.layers.xavier_initializer())
    else:
      kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 32],
                      initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv1', depthwise=depthwise_conv1)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin1 = binary_tanh(norm)   # [-1,1]
    #bin1 = binary_sigmoid(norm) # [0,1]
    bin1 = binary_relu(norm) # [0,1]
    _activation_summary(bin1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(bin1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, pool1.get_shape().as_list()[-1], 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool1, kernel, 'conv')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin2 = binary_tanh(norm)
    #bin2 = binary_sigmoid(norm)
    bin2 = binary_relu(norm)
    _activation_summary(bin2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(bin2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool2, kernel, 'conv')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin3 = binary_tanh(norm)
    #bin3 = binary_sigmoid(norm)
    bin3 = binary_relu(norm)
    _activation_summary(bin3)

  # pool3 (4x4)
  #pool3 = tf.nn.max_pool(bin3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
  #                       padding='SAME', name='pool3')
  pool3 = bin3

  # conv4
  with tf.variable_scope('conv4') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool3, kernel, 'conv4')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    #bin4 = binary_tanh(norm)
    #bin4 = binary_sigmoid(norm)
    bin4 = binary_relu(norm)
    _activation_summary(bin4)

  # pool4 (2x2)
  pool4 = tf.nn.max_pool(bin4, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc5
  label_count = model_settings['label_count']
  with tf.variable_scope('fc5') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = pool4.get_shape()
    reshape = tf.reshape(pool4, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = binfullcon(reshape, weights, 'fc5')
    fc5 = tf.nn.bias_add(fc, biases)
    _activation_summary(fc5)

  if is_training:
    return fc5, dropout_prob
  else:
    return fc5


#################################################################
# 4 stage + straight
def create_tinyex3_conv_model(fingerprint_input, model_settings,
                              is_training,
                              filt_k=1,
                              depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 64)
  assert(input_time_size % 64 == 0)
  input_depth = input_time_size // 64
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 64, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  tf.summary.image("fingerprint",fingerprint_4d)
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 8*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 8*filt_k, 8*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # pool2
  pool2 = tf.nn.max_pool(norm2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 8*filt_k, 8*filt_k],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool2, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm3 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm3)

  # pool3
  pool3 = tf.nn.max_pool(norm3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc4
  if is_training:
    fc_input = tf.nn.dropout(pool3, dropout_prob)
  else:
    fc_input = pool3

  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = tf.matmul(reshape, weights) # no bias
    fc4 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc4)

  if is_training:
    return fc4, dropout_prob
  else:
    return fc4


#################################################################
# VGG type
def create_tinyvgg_conv_model(fingerprint_input, model_settings,
                              is_training,
                              filt_k=1,
                              depthwise_conv1=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 64)
  assert(input_time_size % 64 == 0)
  input_depth = input_time_size // 64
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 64, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  tf.summary.image("fingerprint",fingerprint_4d)
  print(fingerprint_4d.get_shape().as_list())



  #depth = [16, 16, 20, 20, 24, 24]  # Filter, one word
  depth = [16, 16, 20, 20, 20, 24]  # multi words; 32KB for activation, 64KB for program

  ####################################################################
  # Quantization layers
  ####################################################################
  if True: # 8b weight; 8b activation
    fl_w_bin = 8
    fl_a_bin = 8 
    ml_w_bin = 8
    ml_a_bin = 8
    ll_w_bin = 8
    ll_a_bin = 16 # 16b results

    min_rng =  0.0 # range of quanized activation
    max_rng =  2.0

    bias_on = False # no bias for T+

  ####################################################################
  fire1 = _fire_layer('fire1', fingerprint_4d, oc=depth[0], freeze=False, w_bin=fl_w_bin, a_bin=fl_a_bin,                
                                               min_rng=min_rng, max_rng=max_rng, bias_on=bias_on, is_training=is_training)

  fire2 = _fire_layer('fire2', fire1,          oc=depth[1], freeze=False, w_bin=ml_w_bin, a_bin=ml_a_bin, pool_en=False, 
                                               min_rng=min_rng, max_rng=max_rng, bias_on=bias_on, is_training=is_training)

  fire3 = _fire_layer('fire3', fire2,          oc=depth[2], freeze=False, w_bin=ml_w_bin, a_bin=ml_a_bin,                
                                               min_rng=min_rng, max_rng=max_rng, bias_on=bias_on, is_training=is_training)
  
  fire4 = _fire_layer('fire4', fire3,          oc=depth[3], freeze=False, w_bin=ml_w_bin, a_bin=ml_a_bin, pool_en=False, 
                                               min_rng=min_rng, max_rng=max_rng, bias_on=bias_on, is_training=is_training)

  fire5 = _fire_layer('fire5', fire4,          oc=depth[4], freeze=False, w_bin=ml_w_bin, a_bin=ml_a_bin,                
                                               min_rng=min_rng, max_rng=max_rng, bias_on=bias_on, is_training=is_training)

  fire6 = _fire_layer('fire6', fire5,          oc=depth[5], freeze=False, w_bin=ml_w_bin, a_bin=ml_a_bin, 
                                               min_rng=min_rng, max_rng=max_rng, bias_on=bias_on, is_training=is_training)
  fire_o = fire6

  ####################################################################
  # full connect
  ####################################################################
  if is_training:
    fc_input = tf.nn.dropout(fire_o, dropout_prob)
  else:
    fc_input = fire_o

  label_count = model_settings['label_count']
  fc4 = _fc_layer('fc4', fc_input, label_count, flatten=True, relu=False, xavier=True, 
                  w_bin=ll_w_bin, a_bin=ll_a_bin, min_rng=min_rng, max_rng=max_rng)

  if is_training:
    return fc4, dropout_prob, fingerprint_4d #, fire1
  else:
    return fc4, fingerprint_4d


def _fire_layer(layer_name, inputs, oc, stddev=0.01, freeze=False, w_bin=16, a_bin=16, pool_en=True, 
                min_rng=-0.5, max_rng=0.5, bias_on=True, is_training=True):

  with tf.variable_scope(layer_name):
    ex3x3 = _conv_layer('conv3x3', inputs, filters=oc, size=3, stride=1, padding='SAME', stddev=stddev, freeze=freeze, 
                        relu=False, w_bin=w_bin, bias_on=bias_on)
    tf.summary.histogram('before_bn', ex3x3) 
    ex3x3 = _batch_norm('bn', ex3x3, phase_train=is_training) 
    tf.summary.histogram('before_relu', ex3x3) 
    ex3x3 = binary_wrapper(ex3x3, a_bin=a_bin, min_rng=min_rng, max_rng=max_rng) 
    tf.summary.histogram('after_relu', ex3x3)
    if pool_en:
      pool = _pooling_layer('pool', ex3x3, size=2, stride=2, padding='SAME')
    else:
      pool = ex3x3
    tf.summary.histogram('pool', pool)
    return pool

def _variable_on_device(name, shape, initializer, trainable=True):
  """Helper to create a Variable.

  Args:
    name: name of the variable
    shape: list of ints
    initializer: initializer for Variable

  Returns:
    Variable Tensor
  """
  # TODO(bichen): fix the hard-coded data type below
  dtype = tf.float32
  if not callable(initializer):
    var = tf.get_variable(name, initializer=initializer, trainable=trainable)
  else:
    var = tf.get_variable(
        name, shape, initializer=initializer, dtype=dtype, trainable=trainable)
  return var

def _variable_with_weight_decay(name, shape, wd, initializer, trainable=True):
  """Helper to create an initialized Variable with weight decay.

  Note that the Variable is initialized with a truncated normal distribution.
  A weight decay is added only if one is specified.

  Args:
    name: name of the variable
    shape: list of ints
    wd: add L2Loss weight decay multiplied by this float. If None, weight
        decay is not added for this Variable.

  Returns:
    Variable Tensor
  """
  var = _variable_on_device(name, shape, initializer, trainable)
  if wd is not None and trainable:
    weight_decay = tf.multiply(tf.nn.l2_loss(var), wd, name='weight_loss')
    tf.add_to_collection('losses', weight_decay)
  return var

def lin_8b_quant(w, min_rng=-0.5, max_rng=0.5):
  min_clip = tf.rint(min_rng*256/(max_rng-min_rng))
  max_clip = tf.rint(max_rng*256/(max_rng-min_rng)) - 1 # 127, 255

  wq = 256.0 * w / (max_rng - min_rng)              # to expand [min, max] to [-128, 128]
  wq = tf.rint(wq)                                  # integer (quantization)
  wq = tf.clip_by_value(wq, min_clip, max_clip)     # fit into 256 linear quantization
  wq = wq / 256.0 * (max_rng - min_rng)             # back to quantized real number, not integer
  wclip = tf.clip_by_value(w, min_rng, max_rng)     # linear value w/ clipping
  return wclip + tf.stop_gradient(wq - wclip)

def binary_wrapper(x, a_bin=16, min_rng=-0.5, max_rng=0.5): # activation binarization
  #if a_bin == 1:
  #  return binary_tanh(x)
  if a_bin == 8:
    x_quant = lin_8b_quant(x, min_rng=min_rng, max_rng=max_rng)
    return tf.nn.relu(x_quant)
  else:
    return tf.nn.relu(x)


def _conv_layer(layer_name, inputs, filters, size, stride, padding='SAME',
    freeze=False, xavier=False, relu=True, w_bin=16, bias_on=True, stddev=0.001):
  """Convolutional layer operation constructor.

  Args:
    layer_name: layer name.
    inputs: input tensor
    filters: number of output filters.
    size: kernel size.
    stride: stride
    padding: 'SAME' or 'VALID'. See tensorflow doc for detailed description.
    freeze: if true, then do not train the parameters in this layer.
    xavier: whether to use xavier weight initializer or not.
    relu: whether to use relu or not.
    stddev: standard deviation used for random weight initializer.
  Returns:
    A convolutional layer operation.
  """

  with tf.variable_scope(layer_name) as scope:
    channels = inputs.get_shape()[3]

    # re-order the caffe kernel with shape [out, in, h, w] -> tf kernel with
    # shape [h, w, in, out]
    if xavier:
      kernel_init = tf.contrib.layers.xavier_initializer_conv2d()
      bias_init = tf.constant_initializer(0.0)
    else:
      kernel_init = tf.truncated_normal_initializer(
          stddev=stddev, dtype=tf.float32)
      bias_init = tf.constant_initializer(0.0)

    kernel = _variable_with_weight_decay(
      'kernels', shape=[size, size, int(channels), filters], wd=0.0001, initializer=kernel_init, trainable=(not freeze))

    #if w_bin == 1: # binarized conv
    #  kernel_bin = binarize(kernel)
    #  tf.summary.histogram('kernel_bin', kernel_bin)
    #  conv = tf.nn.conv2d(inputs, kernel_bin, [1, stride, stride, 1], padding=padding, name='convolution')
    #  conv_bias = conv
    if w_bin == 8: # 8b quantization
      kernel_quant = lin_8b_quant(kernel)
      tf.summary.histogram('kernel_quant', kernel_quant)
      conv = tf.nn.conv2d(inputs, kernel_quant, [1, stride, stride, 1], padding=padding, name='convolution')

      if bias_on:
        biases = _variable_on_device('biases', [filters], bias_init, trainable=(not freeze))
        biases_quant = lin_8b_quant(biases)
        tf.summary.histogram('biases_quant', biases_quant)
        conv_bias = tf.nn.bias_add(conv, biases_quant, name='bias_add')
      else:
        conv_bias = conv
    else: # 16b quantization
      conv = tf.nn.conv2d(inputs, kernel, [1, stride, stride, 1], padding=padding, name='convolution')
      if bias_on:
        biases = _variable_on_device('biases', [filters], bias_init, trainable=(not freeze))
        conv_bias = tf.nn.bias_add(conv, biases, name='bias_add')
      else:
        conv_bias = conv
  
    if relu:
      out = tf.nn.relu(conv_bias, 'relu')
    else:
      out = conv_bias

    return out

def _pooling_layer(layer_name, inputs, size, stride, padding='SAME'):
  """Pooling layer operation constructor.

  Args:
    layer_name: layer name.
    inputs: input tensor
    size: kernel size.
    stride: stride
    padding: 'SAME' or 'VALID'. See tensorflow doc for detailed description.
  Returns:
    A pooling layer operation.
  """

  with tf.variable_scope(layer_name) as scope:
    out =  tf.nn.max_pool(inputs, 
                          ksize=[1, size, size, 1], 
                          strides=[1, stride, stride, 1],
                          padding=padding)
    return out

def _batch_norm(name, x, phase_train=True): # works well w/ phase_train python variable
  with tf.variable_scope(name):
    params_shape = [x.get_shape()[-1]]

    beta  = tf.get_variable('beta',  params_shape, tf.float32, initializer=tf.constant_initializer(0.0, tf.float32))
    gamma = tf.get_variable('gamma', params_shape, tf.float32, initializer=tf.constant_initializer(1.0, tf.float32))
    tf.summary.histogram('bn_gamma', gamma)
    tf.summary.histogram('bn_beta',  beta )

    control_inputs = []

    if phase_train:
      mean, variance = tf.nn.moments(x, [0, 1, 2], name='moments')

      moving_mean = tf.get_variable(
          'moving_mean', params_shape, tf.float32,
          initializer=tf.constant_initializer(0.0, tf.float32), trainable=False)
      moving_variance = tf.get_variable(
          'moving_variance', params_shape, tf.float32,
          initializer=tf.constant_initializer(1.0, tf.float32), trainable=False)

      update_moving_mean = moving_averages.assign_moving_average(moving_mean, mean, 0.9)
      update_moving_var  = moving_averages.assign_moving_average(moving_variance, variance, 0.9)
      control_inputs = [update_moving_mean, update_moving_var]
    else:
      mean = tf.get_variable(
          'moving_mean', params_shape, tf.float32,
          initializer=tf.constant_initializer(0.0, tf.float32), trainable=False)
      variance = tf.get_variable(
          'moving_variance', params_shape, tf.float32,
          initializer=tf.constant_initializer(1.0, tf.float32), trainable=False)
   
    #self.model_params += [gamma, beta, mean, variance] # <- to save in snapshot
    with tf.control_dependencies(control_inputs):
      y = tf.nn.batch_normalization(x, mean, variance, beta, gamma, 0.001)
    y.set_shape(x.get_shape())
    #return y, [gamma, beta, mean, variance]
    return y


def _fc_layer(layer_name, inputs, hiddens, flatten=False, relu=True, xavier=False, stddev=0.001, w_bin=16, a_bin=16, 
              min_rng=0.0, max_rng=2.0):
  """Fully connected layer operation constructor.

  Args:
    layer_name: layer name.
    inputs: input tensor
    hiddens: number of (hidden) neurons in this layer.
    flatten: if true, reshape the input 4D tensor of shape 
        (batch, height, weight, channel) into a 2D tensor with shape 
        (batch, -1). This is used when the input to the fully connected layer
        is output of a convolutional layer.
    relu: whether to use relu or not.
    xavier: whether to use xavier weight initializer or not.
    stddev: standard deviation used for random weight initializer.
  Returns:
    A fully connected layer operation.
  """

  with tf.variable_scope(layer_name) as scope:
    input_shape = inputs.get_shape().as_list()
    if flatten:
      dim = input_shape[1]*input_shape[2]*input_shape[3]
      inputs = tf.reshape(inputs, [-1, dim])
    else:
      dim = input_shape[1]

    if xavier:
      kernel_init = tf.contrib.layers.xavier_initializer()
      bias_init = tf.constant_initializer(0.0)
    else:
      kernel_init = tf.truncated_normal_initializer(stddev=stddev, dtype=tf.float32)
      bias_init = tf.constant_initializer(0.0)

    weights = _variable_with_weight_decay('weights', shape=[dim, hiddens], wd=0.0001, initializer=kernel_init)
    biases = _variable_on_device('biases', [hiddens], bias_init)

    #====================
    if w_bin == 8: # 8b quantization
      weights_quant = lin_8b_quant(weights)
    else: # 16b quantization
      weights_quant = weights
    tf.summary.histogram('weights_quant', weights_quant)
    #====================
    # no quantization on bias since it will be added to the 16b MUL output
    #====================

    outputs = tf.nn.bias_add(tf.matmul(inputs, weights_quant), biases)
    tf.summary.histogram('outputs', outputs)

    if a_bin == 8:
      outputs_quant = lin_8b_quant(outputs, min_rng=min_rng, max_rng=max_rng)
    else:
      outputs_quant = outputs
    tf.summary.histogram('outputs_quant', outputs_quant)

    if relu:
      outputs = tf.nn.relu(outputs_quant, 'relu')

    # count layer stats

    return outputs


def create_binary_weights3_conv_model(fingerprint_input, model_settings,
                             is_training):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv-> pool -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv1', depthwise=depthwise_conv1)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv1 = tf.nn.relu(norm)
    _activation_summary(conv1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(conv1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool1, kernel, 'conv2')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv2 = tf.nn.relu(norm)
    _activation_summary(conv2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(conv2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool2, kernel, 'conv3')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    conv3 = tf.nn.relu(norm)
    _activation_summary(conv3)

  # pool3 (4x4)
  pool3 = tf.nn.max_pool(conv3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool3')

  # fc4
  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = pool3.get_shape()
    reshape = tf.reshape(pool3, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = binfullcon(reshape, weights, 'fc4')
    fc4 = tf.nn.bias_add(fc, biases)
    _activation_summary(fc4)

  if is_training:
    return fc4, dropout_prob
  else:
    return fc4


def create_binary3_conv_model(fingerprint_input, model_settings,
                              is_training,
                              no_pool3=False,
                              normw=False, stochastic=False):
  """Builds a convolutional model with low compute requirements.

  (fingerprint_input) -> conv -> pool -> conv -> pool -> conv -> conv-> pool -> fc

  """
  assert normw == True
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  assert(input_frequency_size == 32)
  assert(input_time_size % 32 == 0)
  input_depth = input_time_size // 32
  # HCW  (whole picture in one plane)
  _fingerprint_4d = tf.reshape(fingerprint_input,
                               [-1, 32, input_depth, input_frequency_size])
  fingerprint_4d = tf.transpose(_fingerprint_4d, perm=[0, 1, 3, 2])
  print(fingerprint_4d.get_shape().as_list())

  # conv1
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, input_depth, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(fingerprint_4d, kernel, 'conv', normw=normw, stochastic=stochastic)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    bin1 = binary_relu(norm)
    _activation_summary(bin1)

  # pool1 (16x16)
  pool1 = tf.nn.max_pool(bin1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool1, kernel, 'conv', normw=normw, stochastic=stochastic)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    bin2 = binary_relu(norm)
    _activation_summary(bin2)

  # pool2 (8x8)
  pool2 = tf.nn.max_pool(bin2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool2')

  # conv3
  with tf.variable_scope('conv3') as scope:
    kernel = tf.get_variable('weights', shape=[3, 3, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = binconv2d(pool2, kernel, 'conv', normw=normw, stochastic=stochastic)
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    bin3 = binary_relu(norm)
    _activation_summary(bin3)

  # pool3 (4x4)
  if no_pool3:
    pool3 = bin3
  else:
    pool3 = tf.nn.max_pool(bin3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                           padding='SAME', name='pool3')

  # fc4
  label_count = model_settings['label_count']
  with tf.variable_scope('fc4') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = pool3.get_shape()
    reshape = tf.reshape(pool3, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    # NOTE: no normalization in last layer
    fc = binfullcon(reshape, weights, 'fc4', normw=False, stochastic=stochastic)
    fc4 = tf.nn.bias_add(fc, biases)
    _activation_summary(fc4)

  if is_training:
    return fc4, dropout_prob
  else:
    return fc4


#################################################################
# large filter
def create_ex_conv_model(fingerprint_input, model_settings,
                         is_training):
  """Builds a convolutional model

  (fingerprint_input) -> conv -> pool -> conv -> fc

  """
  if is_training:
    dropout_prob = tf.placeholder(tf.float32, name='dropout_prob')
  input_frequency_size = model_settings['dct_coefficient_count']
  input_time_size = model_settings['spectrogram_length']
  fingerprint_4d = tf.reshape(fingerprint_input,
                              [-1, input_time_size, input_frequency_size, 1])

  # conv1
  with tf.variable_scope('conv1') as scope:
    kernel = tf.get_variable('weights', shape=[16, 8, 1, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(fingerprint_4d, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm1 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm1)

  # pool1
  pool1 = tf.nn.max_pool(norm1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1],
                         padding='SAME', name='pool1')

  # conv2
  with tf.variable_scope('conv2') as scope:
    kernel = tf.get_variable('weights', shape=[8, 4, 64, 64],
                    initializer=tf.contrib.layers.xavier_initializer())
    conv = tf.nn.conv2d(pool1, kernel, [1, 1, 1, 1], padding='SAME')
    norm = batch_norm_wrapper(conv, decay=0.9, epsilon=1e-4,
                              is_training=is_training)
    norm2 = tf.nn.relu(norm, name='relu')
    #_activation_summary(norm2)

  # fc3
  if is_training:
    fc_input = tf.nn.dropout(norm2, dropout_prob)
  else:
    fc_input = norm2

  label_count = model_settings['label_count']
  with tf.variable_scope('fc3') as scope:
    # Move everything into depth so we can perform a single matrix multiply.
    conv_shape = fc_input.get_shape()
    reshape = tf.reshape(fc_input, [-1, conv_shape[1]*conv_shape[2]*conv_shape[3]])
    dim = reshape.get_shape()[1].value
    weights = tf.get_variable('weights', shape=[dim, label_count],
                    initializer=tf.contrib.layers.xavier_initializer())
    biases = tf.get_variable('biases', [label_count], initializer=tf.constant_initializer(0.1))
    fc = tf.matmul(reshape, weights) # no bias
    fc3 = tf.nn.bias_add(fc, biases)
    #_activation_summary(fc3)

  if is_training:
    return fc3, dropout_prob
  else:
    return fc3


