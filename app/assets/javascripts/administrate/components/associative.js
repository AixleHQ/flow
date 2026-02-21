$(function () {
  $('.field-unit--belongs-to select').selectize({});
  $('.field-unit--has-many select').selectize({
    plugins: ['remove_button'],
  });
  $('.field-unit--polymorphic select').selectize({});
});
