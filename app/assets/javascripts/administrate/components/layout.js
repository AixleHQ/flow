$(function() {
  $('.sign-out-link').click(function(e) {
    e.preventDefault();

    $.ajax({
      url: $(this).attr('href'),
      type: 'DELETE',
      success: function(response) {
        window.location.href = '/';
      }
    });
  });
});
