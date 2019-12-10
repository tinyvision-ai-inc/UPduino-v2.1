# -*- coding: utf-8 -*-
from __future__ import absolute_import
import tensorflow as tf


def round_through(x, stochastic=False):
    '''Element-wise rounding to the closest integer with full gradient propagation.
    A trick from [Sergey Ioffe](http://stackoverflow.com/a/36480182)
    '''
    if stochastic:
        rounded = tf.ceil(x - tf.random_uniform(tf.shape(x), dtype=x.dtype))
        return x + tf.stop_gradient(rounded - x)
    else: 
        rounded = tf.rint(x)
        return x + tf.stop_gradient(rounded - x)


def _hard_sigmoid(x):
    '''Hard sigmoid different from the more conventional form (see definition of K.hard_sigmoid).

    # Reference:
    - [BinaryNet: Training Deep Neural Networks with Weights and Activations Constrained to +1 or -1, Courbariaux et al. 2016](http://arxiv.org/abs/1602.02830}

    '''
    x = (0.5 * x) + 0.5
    #x = (0.5 * x) + 0.50001
    return tf.clip_by_value(x, 0, 1)


def binary_sigmoid(x):
    '''Binary hard sigmoid for training binarized neural network.

    # Reference:
    - [BinaryNet: Training Deep Neural Networks with Weights and Activations Constrained to +1 or -1, Courbariaux et al. 2016](http://arxiv.org/abs/1602.02830}

    '''
    return round_through(_hard_sigmoid(x), False)


def binary_tanh(x, stochastic=False):
    '''Binary hard sigmoid for training binarized neural network.
     The neurons' activations binarization function
     It behaves like the sign function during forward propagation
     And like:
        hard_tanh(x) = 2 * _hard_sigmoid(x) - 1 
        clear gradient when |x| > 1 during back propagation

    # Reference:
    - [BinaryNet: Training Deep Neural Networks with Weights and Activations Constrained to +1 or -1, Courbariaux et al. 2016](http://arxiv.org/abs/1602.02830}

    '''
    return 2 * round_through(_hard_sigmoid(x), stochastic) - 1


def binarize(W, normalize=False, stochastic=True):
    '''The weights' binarization function, 

    # Reference:
    - [BinaryNet: Training Deep Neural Networks with Weights and Activations Constrained to +1 or -1, Courbariaux et al. 2016](http://arxiv.org/abs/1602.02830}

    '''
    Wb = binary_tanh(W, stochastic)
    if normalize:
        # (H,W,C,N)
        dim = Wb.get_shape().as_list()
        ch_size = reduce(lambda x, y: x*y, dim[:-1])    # H*W*C
        w_scale = tf.reduce_sum(tf.abs(W), [i for i in range(len(dim[:-1]))]) / ch_size
        w_scale_mat = tf.reshape(tf.tile(w_scale, [ch_size]), tf.shape(Wb))
        sWb = tf.multiply(Wb, w_scale_mat)
        return sWb
    return Wb


#------------------------------------------------------------------------------
def binary_relu(x):
    '''Binary ReLU (0,1)
    '''
    return round_through(tf.clip_by_value(tf.nn.relu(x), 0, 1), False)

def quatery_relu(x):
    '''Quatery ReLU (0,1,2,4)
    '''
    y = tf.clip_by_value(tf.nn.relu(x), 0, 4)
    rounded = tf.where(tf.greater_equal(y, 3.),  tf.fill(tf.shape(y), 4.),
                tf.where(tf.greater_equal(y, 1.5), tf.fill(tf.shape(y), 2.),
                  tf.where(tf.greater_equal(y, 0.5), tf.fill(tf.shape(y), 1.),
                    tf.fill(tf.shape(y), 0.) ) ) )
    return y + tf.stop_gradient(rounded - y)



def range_prelu(x, upper_limit=1., outer_slope=0.0001):
    return tf.where(tf.logical_or(tf.greater(x, upper_limit), tf.less(x, 0.)), x*outer_slope, x)

def binary_prelu(x):
    #y = tf.clip_by_value(tf.nn.relu(x), 0, 1)
    y = range_prelu(x, upper_limit=1.)
    rounded = tf.where(tf.greater_equal(y, 0.5), tf.fill(tf.shape(y), 1.), tf.fill(tf.shape(y), 0.))
    return y + tf.stop_gradient(rounded - y)

def quatery_prelu(x):
    '''Quatery ReLU (0,1,2,4)
             [0..4] --> [0..1]
               0.5  -->  0.125
               1.5  -->  0.375
               3.0  -->  0.75
    '''
    #y = tf.clip_by_value(tf.nn.relu(x), 0, 4)
    y = range_prelu(x, upper_limit=4.)
    rounded = tf.where(tf.greater_equal(y, 3.),  tf.fill(tf.shape(y), 4.),
                tf.where(tf.greater_equal(y, 1.5), tf.fill(tf.shape(y), 2.),
                  tf.where(tf.greater_equal(y, 0.5), tf.fill(tf.shape(y), 1.),
                    tf.fill(tf.shape(y), 0.) ) ) )
    return y + tf.stop_gradient(rounded - y)


def bin_table(x):
    rounded = tf.where(tf.greater_equal(x, 0), tf.fill(tf.shape(x), 1.), tf.fill(tf.shape(x), -1.))
    return x + tf.stop_gradient(rounded - x)


